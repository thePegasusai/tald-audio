import React, { useCallback, useEffect, useState } from 'react';
import styled from '@emotion/styled';
import { useMediaQuery } from '@mui/material';
import { useReducedMotion } from 'framer-motion';
import { colors, spacing, breakpoints, animation } from '../../styles/theme';

// Interfaces
interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
  initialFocusRef?: React.RefObject<HTMLElement>;
  onNavigate: (path: string) => void;
}

interface NavItem {
  id: string;
  label: string;
  icon: React.ReactNode;
  path: string;
  ariaLabel: string;
  shortcut?: string;
  badge?: React.ReactNode;
}

// Styled Components with P3 color space support
const SidebarContainer = styled.aside<{ collapsed: boolean; prefersReducedMotion: boolean }>`
  position: fixed;
  left: 0;
  top: 0;
  height: 100vh;
  width: ${props => props.collapsed ? '72px' : '280px'};
  
  /* P3 color space with fallback */
  background-color: ${colors.background.fallback};
  @supports (color: color(display-p3 0 0 0)) {
    background-color: ${colors.background.primary};
  }
  
  transition: ${props => props.prefersReducedMotion ? 'none' : 
    `width ${animation.duration.normal} ${animation.easing.default}`};
  z-index: 1000;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);

  @media (max-width: ${breakpoints.md.width}) {
    transform: translateX(${props => props.collapsed ? '-100%' : '0'});
  }

  @media (forced-colors: active) {
    border-right: 1px solid ButtonText;
  }
`;

const NavList = styled.ul`
  display: flex;
  flex-direction: column;
  gap: ${spacing.sm};
  padding: ${spacing.md};
  list-style: none;
  margin: 0;
  role: menubar;
  aria-orientation: vertical;
`;

const NavItemContainer = styled.li<{ prefersReducedMotion: boolean }>`
  display: flex;
  align-items: center;
  gap: ${spacing.sm};
  padding: ${spacing.sm} ${spacing.md};
  border-radius: 8px;
  cursor: pointer;
  min-height: 44px; // Accessibility - touch target size

  /* P3 color space with fallback for text */
  color: ${colors.text.primary.fallback};
  @supports (color: color(display-p3 0 0 0)) {
    color: ${colors.text.primary.main};
  }

  transition: ${props => props.prefersReducedMotion ? 'none' : 
    `background-color ${animation.duration.fast} ${animation.easing.default}`};

  &:hover {
    background-color: ${colors.primary.main}15;
  }

  &.active {
    background-color: ${colors.primary.main}30;
  }

  &:focus-visible {
    outline: 2px solid ${colors.primary.main};
    outline-offset: -2px;
  }

  @media (forced-colors: active) {
    &:hover, &.active {
      border: 1px solid ButtonText;
    }
  }
`;

const IconWrapper = styled.span`
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  flex-shrink: 0;
`;

const Label = styled.span<{ collapsed: boolean }>`
  white-space: nowrap;
  opacity: ${props => props.collapsed ? 0 : 1};
  visibility: ${props => props.collapsed ? 'hidden' : 'visible'};
  transition: opacity ${animation.duration.fast} ${animation.easing.default};
`;

const Badge = styled.span`
  margin-left: auto;
  padding: ${spacing.xs} ${spacing.sm};
  border-radius: 12px;
  font-size: 12px;
  background-color: ${colors.primary.main}20;
  color: ${colors.primary.main};
`;

// Navigation items configuration
const navItems: NavItem[] = [
  {
    id: 'dashboard',
    label: 'Dashboard',
    icon: '🎛️',
    path: '/dashboard',
    ariaLabel: 'Navigate to dashboard',
    shortcut: 'Alt+1'
  },
  {
    id: 'audio-controls',
    label: 'Audio Controls',
    icon: '🎚️',
    path: '/audio-controls',
    ariaLabel: 'Navigate to audio controls',
    shortcut: 'Alt+2'
  },
  {
    id: 'profiles',
    label: 'Profiles',
    icon: '👤',
    path: '/profiles',
    ariaLabel: 'Navigate to profiles',
    shortcut: 'Alt+3'
  },
  {
    id: 'visualization',
    label: 'Visualization',
    icon: '📊',
    path: '/visualization',
    ariaLabel: 'Navigate to visualization',
    shortcut: 'Alt+4'
  },
  {
    id: 'settings',
    label: 'Settings',
    icon: '⚙️',
    path: '/settings',
    ariaLabel: 'Navigate to settings',
    shortcut: 'Alt+5',
    badge: 'New'
  }
];

export const Sidebar: React.FC<SidebarProps> = ({
  collapsed,
  onToggle,
  initialFocusRef,
  onNavigate
}) => {
  const [activeItem, setActiveItem] = useState<string>('');
  const [focusedItemIndex, setFocusedItemIndex] = useState<number>(-1);
  const isMobile = useMediaQuery(breakpoints.md.query);
  const prefersReducedMotion = useReducedMotion();

  const handleNavigation = useCallback((path: string, event: React.MouseEvent | React.KeyboardEvent) => {
    event.preventDefault();
    onNavigate(path);
    
    if (isMobile) {
      onToggle();
    }

    const itemId = navItems.find(item => item.path === path)?.id;
    if (itemId) {
      setActiveItem(itemId);
      // Announce navigation to screen readers
      const announcement = document.createElement('div');
      announcement.setAttribute('role', 'status');
      announcement.setAttribute('aria-live', 'polite');
      announcement.textContent = `Navigated to ${itemId}`;
      document.body.appendChild(announcement);
      setTimeout(() => document.body.removeChild(announcement), 1000);
    }
  }, [isMobile, onNavigate, onToggle]);

  const handleKeyboardNavigation = useCallback((event: React.KeyboardEvent) => {
    const { key, altKey } = event;

    // Handle keyboard shortcuts
    if (altKey && /^[1-5]$/.test(key)) {
      event.preventDefault();
      const index = parseInt(key) - 1;
      if (navItems[index]) {
        handleNavigation(navItems[index].path, event);
      }
      return;
    }

    // Arrow key navigation
    switch (key) {
      case 'ArrowDown':
        event.preventDefault();
        setFocusedItemIndex(prev => 
          prev < navItems.length - 1 ? prev + 1 : 0);
        break;
      case 'ArrowUp':
        event.preventDefault();
        setFocusedItemIndex(prev => 
          prev > 0 ? prev - 1 : navItems.length - 1);
        break;
      case 'Enter':
      case ' ':
        event.preventDefault();
        if (focusedItemIndex >= 0) {
          handleNavigation(navItems[focusedItemIndex].path, event);
        }
        break;
    }
  }, [focusedItemIndex, handleNavigation]);

  useEffect(() => {
    if (initialFocusRef?.current) {
      initialFocusRef.current.focus();
    }
  }, [initialFocusRef]);

  return (
    <SidebarContainer 
      collapsed={collapsed}
      prefersReducedMotion={prefersReducedMotion || false}
      role="navigation"
      aria-label="Main navigation"
    >
      <NavList onKeyDown={handleKeyboardNavigation}>
        {navItems.map((item, index) => (
          <NavItemContainer
            key={item.id}
            onClick={(e) => handleNavigation(item.path, e)}
            className={activeItem === item.id ? 'active' : ''}
            prefersReducedMotion={prefersReducedMotion || false}
            tabIndex={0}
            role="menuitem"
            aria-label={item.ariaLabel}
            aria-current={activeItem === item.id ? 'page' : undefined}
            ref={index === focusedItemIndex ? initialFocusRef : undefined}
          >
            <IconWrapper aria-hidden="true">
              {item.icon}
            </IconWrapper>
            <Label collapsed={collapsed}>
              {item.label}
              {item.shortcut && (
                <span className="sr-only">
                  {`, shortcut ${item.shortcut}`}
                </span>
              )}
            </Label>
            {item.badge && !collapsed && (
              <Badge role="status" aria-label="New feature available">
                {item.badge}
              </Badge>
            )}
          </NavItemContainer>
        ))}
      </NavList>
    </SidebarContainer>
  );
};

export default Sidebar;