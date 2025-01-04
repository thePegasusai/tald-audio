import React, { useCallback, useMemo } from 'react';
import styled from '@emotion/styled'; // v11.11.0
import { useMediaQuery } from '@mui/material'; // v5.14.0
import { Button } from '../common/Button';
import { theme } from '../../styles/theme';

// Interfaces
interface HeaderProps {
  onMenuClick?: (event: React.MouseEvent) => void;
  title?: string;
  ariaLabel?: string;
}

// Styled Components
const HeaderContainer = styled.header`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: ${({ theme }) => theme.spacing.xxl};
  background-color: ${({ theme }) => theme.colors.background.primary};
  color: ${({ theme }) => theme.colors.text.primary};
  display: flex;
  align-items: center;
  padding: ${({ theme }) => theme.spacing.md};
  z-index: 1000;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
  transition: height ${({ theme }) => theme.animation.duration.normal} ${({ theme }) => theme.animation.easing.default};

  @media (max-width: ${({ theme }) => theme.breakpoints.sm.width}) {
    height: ${({ theme }) => theme.spacing.xl};
    padding: ${({ theme }) => theme.spacing.sm};
  }

  ${theme.animation.reducedMotion.query} {
    transition: none;
  }
`;

const HeaderTitle = styled.h1`
  font-family: ${({ theme }) => theme.typography.fontFamily.primary};
  font-size: clamp(
    ${({ theme }) => theme.typography.fontSizes.lg},
    5vw,
    ${({ theme }) => theme.typography.fontSizes.xl}
  );
  font-weight: ${({ theme }) => theme.typography.fontWeights.semibold};
  margin: 0 0 0 ${({ theme }) => theme.spacing.md};
  line-height: ${({ theme }) => theme.typography.lineHeights.tight};
  color: ${({ theme }) => theme.colors.text.primary};
  user-select: none;

  @media (max-width: ${({ theme }) => theme.breakpoints.sm.width}) {
    font-size: ${({ theme }) => theme.typography.fontSizes.md};
    margin-left: ${({ theme }) => theme.spacing.sm};
  }
`;

const HeaderControls = styled.div`
  display: flex;
  align-items: center;
  gap: ${({ theme }) => theme.spacing.sm};
  margin-left: auto;
  height: 100%;

  @media (max-width: ${({ theme }) => theme.breakpoints.sm.width}) {
    gap: ${({ theme }) => theme.spacing.xs};
  }

  @media (max-width: ${({ theme }) => theme.breakpoints.xs}) {
    > *:not(:last-child) {
      display: none;
    }
  }
`;

const MenuButton = styled(Button)`
  display: none;

  @media (max-width: ${({ theme }) => theme.breakpoints.sm.width}) {
    display: flex;
    margin-left: ${({ theme }) => theme.spacing.xs};
  }
`;

// Component
export const Header: React.FC<HeaderProps> = React.memo(({
  onMenuClick,
  title = 'TALD UNIA',
  ariaLabel = 'Main navigation header'
}) => {
  const isMobile = useMediaQuery(theme.breakpoints.sm.query);

  const handleMenuClick = useCallback((event: React.MouseEvent) => {
    event.preventDefault();
    onMenuClick?.(event);
  }, [onMenuClick]);

  const headerContent = useMemo(() => (
    <>
      <HeaderTitle>{title}</HeaderTitle>
      <HeaderControls>
        <Button
          variant="transport"
          size="medium"
          aria-label="Audio settings"
        >
          <span aria-hidden="true">🎵</span>
        </Button>
        <Button
          variant="volume"
          size="medium"
          aria-label="Volume control"
        >
          <span aria-hidden="true">🔊</span>
        </Button>
        <Button
          variant="preset"
          size="medium"
          aria-label="User profile"
        >
          <span aria-hidden="true">👤</span>
        </Button>
        {isMobile && (
          <MenuButton
            variant="text"
            size="medium"
            onClick={handleMenuClick}
            aria-label="Open menu"
          >
            <span aria-hidden="true">☰</span>
          </MenuButton>
        )}
      </HeaderControls>
    </>
  ), [isMobile, handleMenuClick, title]);

  return (
    <HeaderContainer
      role="banner"
      aria-label={ariaLabel}
    >
      {headerContent}
    </HeaderContainer>
  );
});

Header.displayName = 'Header';

export default Header;