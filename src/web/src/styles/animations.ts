import { keyframes, css } from '@emotion/react'; // v11.11.0
import { animation, transitions } from './theme';

// Performance optimization constants
const GPU_ACCELERATED_TRANSFORM = 'translate3d(0,0,0)';
const REDUCED_MOTION_QUERY = '@media (prefers-reduced-motion: reduce)';

// Performance optimization decorator
const performanceOptimized = (target: any) => {
  return function(...args: any[]) {
    const keyframe = target.apply(this, args);
    return css`
      ${keyframe};
      will-change: transform, opacity;
      backface-visibility: hidden;
      perspective: 1000;
      ${GPU_ACCELERATED_TRANSFORM};
    `;
  };
};

// Validation decorators
const validateDuration = (target: any) => {
  return function(...args: any[]) {
    const [_, duration] = args;
    if (duration < 200 || duration > 300) {
      console.warn('Animation duration should be between 200-300ms for optimal UX');
    }
    return target.apply(this, args);
  };
};

const validateEasing = (target: any) => {
  return function(...args: any[]) {
    const [_, __, easing] = args;
    if (!easing.includes('cubic-bezier')) {
      console.warn('Use cubic-bezier easing for smooth animations');
    }
    return target.apply(this, args);
  };
};

@performanceOptimized
export const fadeIn = keyframes`
  from {
    opacity: 0;
    ${GPU_ACCELERATED_TRANSFORM};
  }
  to {
    opacity: 1;
    ${GPU_ACCELERATED_TRANSFORM};
  }

  ${REDUCED_MOTION_QUERY} {
    from {
      opacity: 1;
    }
    to {
      opacity: 1;
    }
  }
`;

@performanceOptimized
export const fadeOut = keyframes`
  from {
    opacity: 1;
    ${GPU_ACCELERATED_TRANSFORM};
  }
  to {
    opacity: 0;
    ${GPU_ACCELERATED_TRANSFORM};
  }

  ${REDUCED_MOTION_QUERY} {
    from {
      opacity: 1;
    }
    to {
      opacity: 0;
    }
  }
`;

@performanceOptimized
export const slideIn = (direction: 'left' | 'right' | 'top' | 'bottom', distance: number = 20) => {
  const getTransform = () => {
    switch (direction) {
      case 'left':
        return `translate3d(-${distance}px, 0, 0)`;
      case 'right':
        return `translate3d(${distance}px, 0, 0)`;
      case 'top':
        return `translate3d(0, -${distance}px, 0)`;
      case 'bottom':
        return `translate3d(0, ${distance}px, 0)`;
    }
  };

  return keyframes`
    from {
      transform: ${getTransform()};
      opacity: 0;
    }
    to {
      transform: translate3d(0, 0, 0);
      opacity: 1;
    }

    ${REDUCED_MOTION_QUERY} {
      from {
        transform: translate3d(0, 0, 0);
        opacity: 1;
      }
      to {
        transform: translate3d(0, 0, 0);
        opacity: 1;
      }
    }
  `;
};

@validateDuration
@validateEasing
export const createAnimation = (
  name: keyframes | string,
  duration: number = animation.duration.normal,
  easing: string = animation.easing.default
): string => {
  const baseAnimation = `${name} ${duration}ms ${easing}`;

  return css`
    animation: ${baseAnimation};
    
    ${REDUCED_MOTION_QUERY} {
      animation: none;
      transition: none;
    }

    @supports (animation-timeline: scroll()) {
      animation-timeline: scroll();
      animation-range: entry 25% cover 50%;
    }
  `;
};

// Helper functions for common animation combinations
export const createFadeInAnimation = (duration?: number, easing?: string) => 
  createAnimation(fadeIn, duration, easing);

export const createFadeOutAnimation = (duration?: number, easing?: string) => 
  createAnimation(fadeOut, duration, easing);

export const createSlideInAnimation = (
  direction: 'left' | 'right' | 'top' | 'bottom',
  distance?: number,
  duration?: number,
  easing?: string
) => createAnimation(slideIn(direction, distance), duration, easing);

// Export animation timing presets
export const animationPresets = {
  fastFade: createFadeInAnimation(animation.duration.fast, animation.easing.easeOut),
  normalFade: createFadeInAnimation(animation.duration.normal, animation.easing.default),
  slowFade: createFadeInAnimation(animation.duration.slow, animation.easing.easeIn),
  slideInLeft: createSlideInAnimation('left'),
  slideInRight: createSlideInAnimation('right'),
  slideInTop: createSlideInAnimation('top'),
  slideInBottom: createSlideInAnimation('bottom'),
} as const;