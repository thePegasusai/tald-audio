import React, { useCallback, useEffect, useRef, useState, memo } from 'react';
import styled from '@emotion/styled'; // v11.11.0
import { css } from '@emotion/react'; // v11.11.0
import { Portal } from '@radix-ui/react-portal'; // v1.0.0
import { theme } from '../../styles/theme';

// Constants
const TOOLTIP_Z_INDEX = 1000;
const TOOLTIP_OFFSET = 8;
const TOOLTIP_SHOW_DELAY = 200;
const TOOLTIP_HIDE_DELAY = 100;
const TOOLTIP_TOUCH_DELAY = 500;

// Types
type TooltipPlacement = 'top' | 'right' | 'bottom' | 'left';

interface Position {
  top: number;
  left: number;
  transformOrigin: string;
}

interface TooltipProps {
  children: React.ReactNode;
  content: string | React.ReactNode;
  placement?: TooltipPlacement;
  delay?: number;
  touchDelay?: number;
  disabled?: boolean;
  className?: string;
  ariaLabel?: string;
  id?: string;
}

// Styled components
const TooltipContainer = styled.div<{ isVisible: boolean }>`
  position: absolute;
  z-index: ${TOOLTIP_Z_INDEX};
  max-width: 320px;
  padding: ${theme.spacing.sm};
  background-color: ${theme.colors.background.secondary};
  color: ${theme.colors.text.primary};
  border-radius: 4px;
  font-size: ${theme.typography.fontSizes.sm};
  font-family: ${theme.typography.fontFamily.primary};
  line-height: ${theme.typography.lineHeights.normal};
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
  opacity: ${({ isVisible }) => (isVisible ? 1 : 0)};
  transition: opacity ${theme.animation.duration.normal} ${theme.animation.easing.default};
  pointer-events: none;
  word-wrap: break-word;

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }

  @media (forced-colors: active) {
    border: 1px solid ButtonText;
  }
`;

// Helper function to calculate tooltip position
const getTooltipPosition = (
  triggerRect: DOMRect,
  tooltipRect: DOMRect,
  placement: TooltipPlacement,
  isRTL: boolean
): Position => {
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  let top = 0;
  let left = 0;
  let transformOrigin = '';

  switch (placement) {
    case 'top':
      top = triggerRect.top - tooltipRect.height - TOOLTIP_OFFSET;
      left = triggerRect.left + (triggerRect.width - tooltipRect.width) / 2;
      transformOrigin = 'bottom center';
      break;
    case 'bottom':
      top = triggerRect.bottom + TOOLTIP_OFFSET;
      left = triggerRect.left + (triggerRect.width - tooltipRect.width) / 2;
      transformOrigin = 'top center';
      break;
    case 'left':
      top = triggerRect.top + (triggerRect.height - tooltipRect.height) / 2;
      left = triggerRect.left - tooltipRect.width - TOOLTIP_OFFSET;
      transformOrigin = 'right center';
      break;
    case 'right':
      top = triggerRect.top + (triggerRect.height - tooltipRect.height) / 2;
      left = triggerRect.right + TOOLTIP_OFFSET;
      transformOrigin = 'left center';
      break;
  }

  // Viewport boundary detection
  if (left < 0) {
    left = TOOLTIP_OFFSET;
  } else if (left + tooltipRect.width > viewportWidth) {
    left = viewportWidth - tooltipRect.width - TOOLTIP_OFFSET;
  }

  if (top < 0) {
    top = TOOLTIP_OFFSET;
  } else if (top + tooltipRect.height > viewportHeight) {
    top = viewportHeight - tooltipRect.height - TOOLTIP_OFFSET;
  }

  // RTL support
  if (isRTL) {
    left = viewportWidth - left - tooltipRect.width;
  }

  return { top, left, transformOrigin };
};

const Tooltip: React.FC<TooltipProps> = memo(({
  children,
  content,
  placement = 'top',
  delay = TOOLTIP_SHOW_DELAY,
  touchDelay = TOOLTIP_TOUCH_DELAY,
  disabled = false,
  className,
  ariaLabel,
  id,
}) => {
  const [isVisible, setIsVisible] = useState(false);
  const [position, setPosition] = useState<Position | null>(null);
  const triggerRef = useRef<HTMLDivElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const timeoutRef = useRef<NodeJS.Timeout>();
  const touchTimeoutRef = useRef<NodeJS.Timeout>();
  const isRTL = document.dir === 'rtl';

  const showTooltip = useCallback(() => {
    if (disabled || !content) return;
    
    timeoutRef.current = setTimeout(() => {
      if (triggerRef.current && tooltipRef.current) {
        const triggerRect = triggerRef.current.getBoundingClientRect();
        const tooltipRect = tooltipRef.current.getBoundingClientRect();
        const newPosition = getTooltipPosition(triggerRect, tooltipRect, placement, isRTL);
        setPosition(newPosition);
        setIsVisible(true);
      }
    }, delay);
  }, [disabled, content, delay, placement, isRTL]);

  const hideTooltip = useCallback(() => {
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }
    if (touchTimeoutRef.current) {
      clearTimeout(touchTimeoutRef.current);
    }
    setIsVisible(false);
  }, []);

  const handleTouchStart = useCallback(() => {
    if (disabled || !content) return;
    
    touchTimeoutRef.current = setTimeout(() => {
      showTooltip();
    }, touchDelay);
  }, [disabled, content, touchDelay, showTooltip]);

  const handleTouchEnd = useCallback(() => {
    if (touchTimeoutRef.current) {
      clearTimeout(touchTimeoutRef.current);
    }
    hideTooltip();
  }, [hideTooltip]);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      if (touchTimeoutRef.current) {
        clearTimeout(touchTimeoutRef.current);
      }
    };
  }, []);

  const tooltipId = id || `tooltip-${Math.random().toString(36).substr(2, 9)}`;

  return (
    <>
      <div
        ref={triggerRef}
        onMouseEnter={showTooltip}
        onMouseLeave={hideTooltip}
        onFocus={showTooltip}
        onBlur={hideTooltip}
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
        aria-describedby={isVisible ? tooltipId : undefined}
        className={className}
      >
        {children}
      </div>
      <Portal>
        <TooltipContainer
          ref={tooltipRef}
          id={tooltipId}
          role="tooltip"
          aria-label={ariaLabel}
          isVisible={isVisible}
          style={position ? {
            top: `${position.top}px`,
            left: `${position.left}px`,
            transformOrigin: position.transformOrigin,
          } : undefined}
        >
          {content}
        </TooltipContainer>
      </Portal>
    </>
  );
});

Tooltip.displayName = 'Tooltip';

export type { TooltipProps };
export default Tooltip;