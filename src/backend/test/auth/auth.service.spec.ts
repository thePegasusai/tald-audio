import { Test, TestingModule } from '@nestjs/testing'; // ^9.0.0
import { JwtService } from '@nestjs/jwt'; // ^9.0.0
import { UnauthorizedException } from '@nestjs/common'; // ^9.0.0
import { AuthService } from '../../src/auth/auth.service';
import { JwtStrategy } from '../../src/auth/strategies/jwt.strategy';
import { configuration } from '../../src/config/configuration';

describe('AuthService', () => {
  let module: TestingModule;
  let authService: AuthService;
  let jwtService: JwtService;
  const mockConfig = configuration();

  beforeEach(async () => {
    // Create testing module with mocked dependencies
    module = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: JwtService,
          useValue: {
            signAsync: jest.fn(),
            verifyAsync: jest.fn()
          }
        },
        {
          provide: 'CONFIG',
          useValue: mockConfig
        }
      ]
    }).compile();

    authService = module.get<AuthService>(AuthService);
    jwtService = module.get<JwtService>(JwtService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('validateUser', () => {
    it('should successfully validate user with correct credentials', async () => {
      const result = await authService.validateUser('admin', 'hashedPassword123');
      expect(result).toBeDefined();
      expect(result.username).toBe('admin');
      expect(result.roles).toContain('admin');
      expect(result.password).toBeUndefined();
    });

    it('should throw UnauthorizedException for invalid username', async () => {
      await expect(
        authService.validateUser('nonexistent', 'password')
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw UnauthorizedException for invalid password', async () => {
      await expect(
        authService.validateUser('admin', 'wrongpassword')
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should implement brute force protection after max attempts', async () => {
      const attempts = 6;
      for (let i = 0; i < attempts; i++) {
        try {
          await authService.validateUser('admin', 'wrongpassword');
        } catch (error) {
          expect(error).toBeInstanceOf(UnauthorizedException);
        }
      }
      await expect(
        authService.validateUser('admin', 'hashedPassword123')
      ).rejects.toThrow('Account temporarily locked');
    });
  });

  describe('login', () => {
    const mockUser = {
      id: '1',
      username: 'admin',
      roles: ['admin']
    };

    const mockToken = 'mock.jwt.token';

    beforeEach(() => {
      (jwtService.signAsync as jest.Mock).mockResolvedValue(mockToken);
    });

    it('should generate valid JWT token with correct payload', async () => {
      const result = await authService.login(mockUser);
      
      expect(result).toHaveProperty('access_token');
      expect(result.access_token).toBe(mockToken);
      
      expect(jwtService.signAsync).toHaveBeenCalledWith(
        expect.objectContaining({
          sub: mockUser.id,
          username: mockUser.username,
          roles: mockUser.roles,
          iss: mockConfig.jwt.issuer,
          aud: mockConfig.jwt.audience
        }),
        expect.objectContaining({
          algorithm: 'RS256',
          issuer: mockConfig.jwt.issuer,
          audience: mockConfig.jwt.audience,
          expiresIn: mockConfig.jwt.expiration
        })
      );
    });

    it('should include all required JWT claims', async () => {
      await authService.login(mockUser);
      
      const [payload] = (jwtService.signAsync as jest.Mock).mock.calls[0];
      
      expect(payload).toHaveProperty('sub');
      expect(payload).toHaveProperty('username');
      expect(payload).toHaveProperty('roles');
      expect(payload).toHaveProperty('iat');
      expect(payload).toHaveProperty('exp');
      expect(payload).toHaveProperty('iss');
      expect(payload).toHaveProperty('aud');
    });
  });

  describe('verifyToken', () => {
    const mockToken = 'valid.jwt.token';
    const mockPayload = {
      sub: '1',
      username: 'admin',
      roles: ['admin'],
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 3600,
      iss: mockConfig.jwt.issuer,
      aud: mockConfig.jwt.audience
    };

    beforeEach(() => {
      (jwtService.verifyAsync as jest.Mock).mockResolvedValue(mockPayload);
    });

    it('should successfully verify valid token', async () => {
      const result = await authService.verifyToken(mockToken);
      expect(result).toEqual(mockPayload);
    });

    it('should throw UnauthorizedException for blacklisted token', async () => {
      await authService.blacklistToken(mockToken);
      await expect(authService.verifyToken(mockToken))
        .rejects.toThrow('Token has been revoked');
    });

    it('should verify token with correct validation options', async () => {
      await authService.verifyToken(mockToken);
      
      expect(jwtService.verifyAsync).toHaveBeenCalledWith(
        mockToken,
        expect.objectContaining({
          algorithms: ['RS256'],
          issuer: mockConfig.jwt.issuer,
          audience: mockConfig.jwt.audience
        })
      );
    });

    it('should throw UnauthorizedException for invalid token', async () => {
      (jwtService.verifyAsync as jest.Mock).mockRejectedValue(new Error());
      await expect(authService.verifyToken('invalid.token'))
        .rejects.toThrow(UnauthorizedException);
    });
  });

  describe('validateRoles', () => {
    it('should grant access for admin role regardless of required roles', () => {
      const result = authService.validateRoles(
        ['admin'],
        ['user', 'manager']
      );
      expect(result).toBe(true);
    });

    it('should grant access when user has required role', () => {
      const result = authService.validateRoles(
        ['user', 'manager'],
        ['manager']
      );
      expect(result).toBe(true);
    });

    it('should deny access when user lacks required roles', () => {
      const result = authService.validateRoles(
        ['user'],
        ['manager', 'admin']
      );
      expect(result).toBe(false);
    });

    it('should handle empty required roles array', () => {
      const result = authService.validateRoles(
        ['user'],
        []
      );
      expect(result).toBe(false);
    });

    it('should handle empty user roles array', () => {
      const result = authService.validateRoles(
        [],
        ['user']
      );
      expect(result).toBe(false);
    });
  });

  describe('blacklistToken', () => {
    const mockToken = 'token.to.blacklist';

    it('should successfully blacklist a token', async () => {
      await authService.blacklistToken(mockToken);
      await expect(authService.verifyToken(mockToken))
        .rejects.toThrow('Token has been revoked');
    });

    it('should maintain blacklist across multiple operations', async () => {
      await authService.blacklistToken(mockToken);
      await expect(authService.verifyToken(mockToken))
        .rejects.toThrow('Token has been revoked');
      await expect(authService.verifyToken(mockToken))
        .rejects.toThrow('Token has been revoked');
    });
  });
});