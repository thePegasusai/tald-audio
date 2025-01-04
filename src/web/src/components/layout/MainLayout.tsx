import React, { useCallback, useEffect, useState, useRef } from 'react';
import styled from '@emotion/styled'; // v11.11.0
import { useMediaQuery } from '@mui/material'; // v5.14.0
import { useReducedMotion } from 'framer-motion'; // v10.12.0
import { useTheme } from '@emotion/react'; // v11.11.0

import Header from './Header';
import Footer from './Footer';
import Sidebar from './Sidebar';
import { theme } from '../../styles/theme';

// Interfaces
interface MainLayoutProps {
  children: React.ReactNode;
  audioEnabled?: boolean;
  rtl?: boolean;
}

// Styled Components with P3 color space support
const LayoutContainer = styled.div<{ prefersReducedMotion: boolean; rtl: boolean }>`
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  
  /* P3 color space with fallback */
  background-color: ${theme.colors.background.fallback};
  @supports (color: color(display-p3 0 0 0)) {
    background-color: ${theme.colors.background.primary};
  }
  
  color: ${theme.colors.text.primary};
  transition: ${props => props.prefersReducedMotion ? 'none' : 
    `background-color ${theme.animation.duration.normal} ${theme.animation.easing.default}`};
  direction: ${props => props.rtl ? 'rtl' : 'ltr'};

  @media (forced-colors: active) {
    border: 1px solid ButtonText;
  }
`;

const MainContent = styled.main<{
  sidebarCollapsed: boolean;
  prefersReducedMotion: boolean;
  rtl: boolean;
}>`
  flex: 1;
  margin-${props => props.rtl ? 'right' : 'left'}: ${props => props.sidebarCollapsed ? '72px' : '280px'};
  margin-top: 64px;
  padding: ${theme.spacing.lg};
  transition: ${props => props.prefersReducedMotion ? 'none' : 
    `margin-${props.rtl ? 'right' : 'left'} ${theme.animation.duration.normal} ${theme.animation.easing.default}`};

  @media (max-width: ${theme.breakpoints.md.width}) {
    margin-${props => props.rtl ? 'right' : 'left'}: 0;
    padding: ${theme.spacing.md};
  }

  &:focus {
    outline: none;
  }

  &:focus-visible {
    outline: 2px solid ${theme.colors.primary.main};
    outline-offset: -2px;
  }
`;

const SkipLink = styled.a`
  position: fixed;
  top: -100%;
  left: 0;
  z-index: 2000;
  padding: ${theme.spacing.md};
  background-color: ${theme.colors.primary.main};
  color: ${theme.colors.text.primary};
  text-decoration: none;
  
  &:focus {
    top: 0;
  }
`;

export const MainLayout: React.FC<MainLayoutProps> = ({
  children,
  audioEnabled = true,
  rtl = false
}) => {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const mainContentRef = useRef<HTMLElement>(null);
  const sidebarRef = useRef<HTMLElement>(null);
  const isMobile = useMediaQuery(theme.breakpoints.md.query);
  const prefersReducedMotion = useReducedMotion();

  // Handle sidebar toggle
  const handleSidebarToggle = useCallback(() => {
    setSidebarCollapsed(prev => !prev);
    
    // Announce state change to screen readers
    const announcement = document.createElement('div');
    announcement.setAttribute('role', 'status');
    announcement.setAttribute('aria-live', 'polite');
    announcement.textContent = `Sidebar ${sidebarCollapsed ? 'expanded' : 'collapsed'}`;
    document.body.appendChild(announcement);
    setTimeout(() => document.body.removeChild(announcement), 1000);
  }, [sidebarCollapsed]);

  // Handle mobile menu
  const handleMenuClick = useCallback((event: React.MouseEvent) => {
    event.preventDefault();
    setIsMobileMenuOpen(prev => !prev);
  }, []);

  // Handle navigation
  const handleNavigation = useCallback((path: string) => {
    if (isMobile) {
      setIsMobileMenuOpen(false);
    }
    // Navigation logic would be implemented here
  }, [isMobile]);

  // Handle keyboard navigation
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && isMobileMenuOpen) {
        setIsMobileMenuOpen(false);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isMobileMenuOpen]);

  // Update document direction
  useEffect(() => {
    document.documentElement.dir = rtl ? 'rtl' : 'ltr';
  }, [rtl]);

  return (
    <LayoutContainer prefersReducedMotion={prefersReducedMotion || false} rtl={rtl}>
      <SkipLink href="#main-content">
        Skip to main content
      </SkipLink>

      <Header
        onMenuClick={handleMenuClick}
        title="TALD UNIA"
        ariaLabel="Main header with audio controls"
      />

      <Sidebar
        collapsed={isMobile ? isMobileMenuOpen : sidebarCollapsed}
        onToggle={handleSidebarToggle}
        initialFocusRef={sidebarRef}
        onNavigate={handleNavigation}
      />

      <MainContent
        id="main-content"
        ref={mainContentRef}
        sidebarCollapsed={sidebarCollapsed}
        prefersReducedMotion={prefersReducedMotion || false}
        rtl={rtl}
        role="main"
        aria-label="Main content"
        tabIndex={-1}
      >
        {children}
      </MainContent>

      <Footer />
    </LayoutContainer>
  );
};

export default MainLayout;