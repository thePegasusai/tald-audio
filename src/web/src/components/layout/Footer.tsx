import React from 'react';
import styled from '@emotion/styled';
import { theme } from '../../styles/theme';

// Styled components with responsive and accessible design
const FooterContainer = styled.footer`
  display: flex;
  flex-direction: ${props => props.theme.breakpoints.sm.query ? 'column' : 'row'};
  align-items: center;
  justify-content: space-between;
  padding: ${theme.spacing.md};
  background-color: ${theme.colors.background.secondary};
  border-top: 1px solid ${theme.colors.text.disabled};
  color: ${theme.colors.text.secondary};
  font-family: ${theme.typography.fontFamily.secondary};
  font-size: ${theme.typography.fontSizes.sm};
  gap: ${theme.spacing.md};

  ${theme.breakpoints.sm.query} {
    padding: ${theme.spacing.sm};
    text-align: center;
  }
`;

const Copyright = styled.div`
  display: flex;
  align-items: center;
  gap: ${theme.spacing.sm};
  color: ${theme.colors.text.primary};

  ${theme.breakpoints.sm.query} {
    justify-content: center;
  }
`;

const Version = styled.div`
  display: flex;
  align-items: center;
  gap: ${theme.spacing.sm};
  font-weight: ${theme.typography.fontWeights.medium};

  ${theme.breakpoints.sm.query} {
    justify-content: center;
  }
`;

interface StatusProps {
  status: 'online' | 'offline';
}

const Status = styled.div<StatusProps>`
  display: flex;
  align-items: center;
  gap: ${theme.spacing.xs};
  padding: ${theme.spacing.xs} ${theme.spacing.sm};
  border-radius: 4px;
  background-color: ${props => 
    props.status === 'online' 
      ? theme.colors.status.success 
      : theme.colors.status.error};
  color: ${theme.colors.text.primary};
  transition: background-color ${theme.animation.duration.normal} ${theme.animation.easing.default};

  ${theme.breakpoints.sm.query} {
    justify-content: center;
  }

  ${theme.animation.reducedMotion.query} {
    transition-duration: ${theme.animation.reducedMotion.duration.normal};
  }
`;

const Footer: React.FC = () => {
  const currentYear = new Date().getFullYear();
  const version = process.env.REACT_APP_VERSION || '1.0.0';
  const [systemStatus, setSystemStatus] = React.useState<'online' | 'offline'>('online');

  // Update system status when component mounts and handle cleanup
  React.useEffect(() => {
    const checkStatus = () => {
      // Implementation would connect to actual system status endpoint
      // This is a placeholder
      setSystemStatus('online');
    };

    const statusInterval = setInterval(checkStatus, 30000);
    checkStatus();

    return () => clearInterval(statusInterval);
  }, []);

  return (
    <FooterContainer role="contentinfo" aria-label="Application footer">
      <Copyright>
        <span aria-label="Copyright">©</span>
        <span>{currentYear} TALD UNIA. All rights reserved.</span>
      </Copyright>

      <Version>
        <span aria-label="Application version">Version {version}</span>
      </Version>

      <Status 
        status={systemStatus}
        role="status"
        aria-live="polite"
        aria-label={`System status: ${systemStatus}`}
      >
        <span aria-hidden="true">●</span>
        <span>System {systemStatus}</span>
      </Status>
    </FooterContainer>
  );
};

export default Footer;