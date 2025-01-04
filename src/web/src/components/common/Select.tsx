import React, { useCallback, useRef, useState } from 'react';
import styled from '@emotion/styled';
import { css } from '@emotion/react';
import debounce from 'lodash/debounce';
import { theme } from '../../styles/theme';

// Types
interface AudioPreviewData {
  url: string;
  duration: number;
}

interface SelectOption {
  value: string;
  label: string;
  audioPreview?: AudioPreviewData;
}

interface SelectProps {
  options: SelectOption[];
  value?: string;
  onChange: (value: string, audioData?: AudioPreviewData) => void;
  placeholder?: string;
  disabled?: boolean;
  error?: boolean;
  className?: string;
  id?: string;
  name?: string;
  ariaLabel?: string;
  audioPreviewDelay?: number;
  renderOption?: (option: SelectOption) => React.ReactNode;
}

// Styled Components
const StyledSelect = styled.select<{ error?: boolean }>`
  min-height: 44px; // WCAG touch target size
  width: 100%;
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.md};
  font-weight: ${theme.typography.fontWeights.regular};
  color: ${theme.colors.text.primary};
  background-color: ${theme.colors.background.primary};
  border: 2px solid ${props => 
    props.error ? theme.colors.status.error : theme.colors.primary.main};
  border-radius: ${theme.spacing.xs};
  padding: ${theme.spacing.sm} ${theme.spacing.md};
  cursor: pointer;
  appearance: none;
  transition: all ${theme.animation.duration.normal} ${theme.animation.easing.default};

  // P3 color space support
  @supports (color: color(display-p3 0 0 0)) {
    color: ${theme.colors.text.primary};
    background-color: ${theme.colors.background.primary};
    border-color: ${props => 
      props.error ? theme.colors.status.error : theme.colors.primary.main};
  }

  &:hover:not(:disabled) {
    border-color: ${props => 
      props.error ? theme.colors.status.error : theme.colors.primary.light};
    background-color: ${theme.colors.background.secondary};
  }

  &:focus {
    outline: none;
    box-shadow: 0 0 0 2px ${props => 
      props.error ? theme.colors.status.error : theme.colors.primary.light};
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    background-color: ${theme.colors.background.secondary};
  }

  // Reduced motion support
  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }

  // Custom scrollbar styling
  &::-webkit-scrollbar {
    width: 8px;
  }

  &::-webkit-scrollbar-track {
    background: ${theme.colors.background.secondary};
  }

  &::-webkit-scrollbar-thumb {
    background: ${theme.colors.primary.main};
    border-radius: 4px;
  }

  // Option styling
  option {
    padding: ${theme.spacing.sm} ${theme.spacing.md};
    background-color: ${theme.colors.background.primary};
    color: ${theme.colors.text.primary};

    &:hover {
      background-color: ${theme.colors.primary.main};
    }
  }
`;

const SelectWrapper = styled.div`
  position: relative;
  width: 100%;

  &::after {
    content: '';
    position: absolute;
    right: ${theme.spacing.md};
    top: 50%;
    transform: translateY(-50%);
    width: 0;
    height: 0;
    border-left: 6px solid transparent;
    border-right: 6px solid transparent;
    border-top: 6px solid ${theme.colors.text.primary};
    pointer-events: none;
  }
`;

const VisuallyHidden = styled.span`
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
`;

// Component
export const Select: React.FC<SelectProps> = ({
  options,
  value,
  onChange,
  placeholder,
  disabled = false,
  error = false,
  className,
  id,
  name,
  ariaLabel,
  audioPreviewDelay = 300,
  renderOption,
}) => {
  const [liveRegionText, setLiveRegionText] = useState('');
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // Create audio element for previews
  React.useEffect(() => {
    audioRef.current = new Audio();
    audioRef.current.volume = 0.5; // Set default preview volume
    
    return () => {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }
    };
  }, []);

  // Debounced audio preview handler
  const previewAudio = useCallback(
    debounce((audioData?: AudioPreviewData) => {
      if (audioRef.current && audioData?.url) {
        audioRef.current.pause();
        audioRef.current.src = audioData.url;
        audioRef.current.play().catch(() => {
          // Handle playback errors silently
        });
      }
    }, audioPreviewDelay),
    [audioPreviewDelay]
  );

  // Handle select change
  const handleChange = (event: React.ChangeEvent<HTMLSelectElement>) => {
    event.preventDefault();
    const newValue = event.target.value;
    const selectedOption = options.find(opt => opt.value === newValue);
    
    if (selectedOption) {
      // Update live region for screen readers
      setLiveRegionText(`Selected: ${selectedOption.label}`);
      
      // Preview audio if available
      if (selectedOption.audioPreview) {
        previewAudio(selectedOption.audioPreview);
      }
      
      // Call onChange handler
      onChange(newValue, selectedOption.audioPreview);
    }
  };

  // Handle keyboard navigation
  const handleKeyDown = (event: React.KeyboardEvent<HTMLSelectElement>) => {
    const target = event.target as HTMLSelectElement;
    const currentIndex = target.selectedIndex;

    switch (event.key) {
      case 'ArrowDown':
      case 'ArrowUp':
        event.preventDefault();
        const newIndex = event.key === 'ArrowDown' 
          ? Math.min(currentIndex + 1, options.length - 1)
          : Math.max(currentIndex - 1, 0);
        
        const previewOption = options[newIndex];
        if (previewOption?.audioPreview) {
          previewAudio(previewOption.audioPreview);
        }
        break;

      case 'Escape':
        target.blur();
        break;
    }
  };

  return (
    <SelectWrapper className={className}>
      <StyledSelect
        id={id}
        name={name}
        value={value}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        disabled={disabled}
        error={error}
        aria-label={ariaLabel}
        aria-invalid={error}
        aria-describedby={error ? `${id}-error` : undefined}
      >
        {placeholder && (
          <option value="" disabled>
            {placeholder}
          </option>
        )}
        {options.map(option => (
          <option key={option.value} value={option.value}>
            {renderOption ? renderOption(option) : option.label}
          </option>
        ))}
      </StyledSelect>
      
      {/* Live region for accessibility */}
      <VisuallyHidden 
        role="status" 
        aria-live="polite"
      >
        {liveRegionText}
      </VisuallyHidden>
    </SelectWrapper>
  );
};

export default Select;