import React, { useCallback, useEffect, useRef } from 'react';
import styled from '@emotion/styled';
import { css } from '@emotion/react';
import FocusTrap from 'focus-trap-react';
import { theme } from '../../styles/theme';
import { fadeIn } from '../../styles/animations';

// Constants
const MODAL_Z_INDEX = 1000;
const OVERLAY_OPACITY = 0.75;
const ANIMATION_DURATION = theme.animation.duration.normal;
const ANIMATION_EASING = theme.animation.easing.default;

// Types
interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
  ariaLabel?: string;
  ariaDescribedBy?: string;
  closeOnOverlayClick?: boolean;
  initialFocusRef?: React.RefObject<HTMLElement>;
  finalFocusRef?: React.RefObject<HTMLElement>;
  disableScroll?: boolean;
}

// Styled Components
const ModalOverlay = styled.div<{ isOpen: boolean }>`
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: ${theme.colors.background.primary};
  opacity: ${props => props.isOpen ? OVERLAY_OPACITY : 0};
  z-index: ${MODAL_Z_INDEX};
  animation: ${fadeIn} ${ANIMATION_DURATION} ${ANIMATION_EASING};
  will-change: opacity;
  transform: translateZ(0);
  backface-visibility: hidden;

  @media (prefers-reduced-motion: reduce) {
    animation: none;
  }
`;

const ModalContent = styled.div`
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background-color: ${theme.colors.background.secondary};
  padding: ${theme.spacing.lg};
  border-radius: 8px;
  z-index: ${MODAL_Z_INDEX + 1};
  min-width: 320px;
  max-width: min(90%, 600px);
  max-height: 90vh;
  overflow-y: auto;
  will-change: transform, opacity;
  transform: translateZ(0);
  backface-visibility: hidden;
  box-shadow: 0 8px 16px rgba(0, 0, 0, 0.2);
  color: ${theme.colors.text.primary};
  font-family: ${theme.typography.fontFamily.primary};

  @media ${theme.breakpoints.sm.query} {
    padding: ${theme.spacing.md};
    min-width: 280px;
  }

  @media (prefers-reduced-motion: reduce) {
    animation: none;
  }
`;

const ModalHeader = styled.header`
  margin-bottom: ${theme.spacing.md};
`;

const ModalTitle = styled.h2`
  ${theme.typography.fontSizes.xl};
  font-weight: ${theme.typography.fontWeights.semibold};
  color: ${theme.colors.text.primary};
  margin: 0;
`;

const Modal: React.FC<ModalProps> = ({
  isOpen,
  onClose,
  children,
  title,
  ariaLabel,
  ariaDescribedBy,
  closeOnOverlayClick = true,
  initialFocusRef,
  finalFocusRef,
  disableScroll = true,
}) => {
  const contentRef = useRef<HTMLDivElement>(null);
  const previousActiveElement = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (isOpen && disableScroll) {
      document.body.style.overflow = 'hidden';
      return () => {
        document.body.style.overflow = '';
      };
    }
  }, [isOpen, disableScroll]);

  useEffect(() => {
    if (isOpen) {
      previousActiveElement.current = document.activeElement as HTMLElement;
      if (initialFocusRef?.current) {
        initialFocusRef.current.focus();
      }
    } else if (finalFocusRef?.current) {
      finalFocusRef.current.focus();
    } else if (previousActiveElement.current) {
      previousActiveElement.current.focus();
    }
  }, [isOpen, initialFocusRef, finalFocusRef]);

  const handleEscapeKey = useCallback((event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      onClose();
    }
  }, [onClose]);

  const handleOverlayClick = useCallback((event: React.MouseEvent) => {
    if (event.target === event.currentTarget && closeOnOverlayClick) {
      event.preventDefault();
      onClose();
    }
  }, [onClose, closeOnOverlayClick]);

  if (!isOpen) return null;

  return (
    <FocusTrap
      active={isOpen}
      focusTrapOptions={{
        initialFocus: initialFocusRef?.current || undefined,
        escapeDeactivates: true,
        allowOutsideClick: true,
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel || title}
        aria-describedby={ariaDescribedBy}
      >
        <ModalOverlay
          isOpen={isOpen}
          onClick={handleOverlayClick}
          data-testid="modal-overlay"
        />
        <ModalContent
          ref={contentRef}
          role="document"
          tabIndex={-1}
          data-testid="modal-content"
        >
          {title && (
            <ModalHeader>
              <ModalTitle>{title}</ModalTitle>
            </ModalHeader>
          )}
          {children}
        </ModalContent>
      </div>
    </FocusTrap>
  );
};

export default Modal;