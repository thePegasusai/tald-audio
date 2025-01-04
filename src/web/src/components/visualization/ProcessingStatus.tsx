import React, { memo, useCallback, useEffect, useMemo } from 'react';
import styled from '@emotion/styled'; // v11.11.0
import { useSelector, useDispatch } from 'react-redux'; // v8.1.0
import debounce from 'lodash/debounce'; // v4.17.21
import { ProcessingStatus } from '../../types/visualization.types';
import Tooltip from '../common/Tooltip';
import { updateProcessingStatus, selectProcessingStatus } from '../../store/slices/visualizationSlice';

// Constants for performance thresholds
const CPU_LOAD_WARNING = 30;
const CPU_LOAD_ERROR = 40;
const LATENCY_WARNING = 8;
const LATENCY_ERROR = 10;
const DEFAULT_UPDATE_INTERVAL = 100;

interface ProcessingStatusProps {
  className?: string;
  showTooltips?: boolean;
  updateInterval?: number;
  thresholds?: {
    cpuLoad: number;
    latency: number;
  };
}

// Styled components with theme integration
const StatusContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${({ theme }) => theme.spacing.sm};
  padding: ${({ theme }) => theme.spacing.md};
  background-color: ${({ theme }) => theme.colors.background.secondary};
  border-radius: 4px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  position: relative;
  transition: all 0.2s ease-in-out;

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const MetricRow = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: ${({ theme }) => theme.spacing.md};
  position: relative;
  min-height: 32px;
`;

const MetricLabel = styled.span`
  font-size: ${({ theme }) => theme.typography.fontSizes.sm};
  font-weight: ${({ theme }) => theme.typography.fontWeights.medium};
  color: ${({ theme }) => theme.colors.text.secondary};
  user-select: none;
`;

const MetricValue = styled.span<{ status?: 'normal' | 'warning' | 'error' }>`
  font-size: ${({ theme }) => theme.typography.fontSizes.md};
  font-weight: ${({ theme }) => theme.typography.fontWeights.semibold};
  color: ${({ theme, status }) => 
    status === 'error' ? theme.colors.status.error :
    status === 'warning' ? theme.colors.status.warning :
    theme.colors.text.primary};
  transition: color 0.2s ease-in-out;

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const ProgressBar = styled.div`
  width: 100%;
  height: 4px;
  background-color: ${({ theme }) => theme.colors.background.primary};
  border-radius: 2px;
  overflow: hidden;
  position: relative;
`;

const ProgressIndicator = styled.div<{ value: number; status: string }>`
  position: absolute;
  height: 100%;
  width: ${({ value }) => `${value}%`};
  background-color: ${({ theme, status }) => 
    status === 'error' ? theme.colors.status.error :
    status === 'warning' ? theme.colors.status.warning :
    theme.colors.primary.main};
  transition: width 0.2s ease-in-out, background-color 0.2s ease-in-out;

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const formatMetricValue = (value: number, type: 'cpu' | 'buffer' | 'latency'): string => {
  switch (type) {
    case 'cpu':
      return `${value.toFixed(1)}%`;
    case 'buffer':
      return `${value} samples`;
    case 'latency':
      return `${value.toFixed(1)}ms`;
    default:
      return `${value}`;
  }
};

const getMetricStatus = (value: number, type: 'cpu' | 'latency'): 'normal' | 'warning' | 'error' => {
  const thresholds = type === 'cpu' 
    ? { warning: CPU_LOAD_WARNING, error: CPU_LOAD_ERROR }
    : { warning: LATENCY_WARNING, error: LATENCY_ERROR };

  if (value >= thresholds.error) return 'error';
  if (value >= thresholds.warning) return 'warning';
  return 'normal';
};

const ProcessingStatus: React.FC<ProcessingStatusProps> = memo(({
  className,
  showTooltips = true,
  updateInterval = DEFAULT_UPDATE_INTERVAL,
  thresholds = { cpuLoad: CPU_LOAD_ERROR, latency: LATENCY_ERROR }
}) => {
  const dispatch = useDispatch();
  const status = useSelector(selectProcessingStatus);

  const debouncedUpdateStatus = useMemo(
    () => debounce((newStatus: ProcessingStatus) => {
      dispatch(updateProcessingStatus(newStatus));
    }, updateInterval),
    [dispatch, updateInterval]
  );

  useEffect(() => {
    return () => {
      debouncedUpdateStatus.cancel();
    };
  }, [debouncedUpdateStatus]);

  const renderMetric = useCallback((
    label: string,
    value: number,
    type: 'cpu' | 'buffer' | 'latency',
    tooltipContent?: string
  ) => {
    const formattedValue = formatMetricValue(value, type);
    const status = type === 'buffer' ? 'normal' : getMetricStatus(value, type as 'cpu' | 'latency');
    const progressValue = type === 'cpu' ? value : (value / thresholds[type as 'latency']) * 100;

    const metricContent = (
      <MetricRow>
        <MetricLabel>{label}</MetricLabel>
        <MetricValue status={status} aria-label={`${label}: ${formattedValue}`}>
          {formattedValue}
        </MetricValue>
        {type !== 'buffer' && (
          <ProgressBar role="progressbar" aria-valuenow={value} aria-valuemin={0} aria-valuemax={100}>
            <ProgressIndicator value={progressValue} status={status} />
          </ProgressBar>
        )}
      </MetricRow>
    );

    return showTooltips && tooltipContent ? (
      <Tooltip content={tooltipContent} placement="left">
        {metricContent}
      </Tooltip>
    ) : metricContent;
  }, [showTooltips, thresholds]);

  return (
    <StatusContainer className={className} role="region" aria-label="Processing Status">
      {renderMetric(
        'CPU Load',
        status.cpuLoad,
        'cpu',
        'Current CPU utilization for audio processing'
      )}
      {renderMetric(
        'Buffer Size',
        status.bufferSize,
        'buffer',
        'Current audio buffer size in samples'
      )}
      {renderMetric(
        'Latency',
        status.latency,
        'latency',
        'Current audio processing latency'
      )}
    </StatusContainer>
  );
});

ProcessingStatus.displayName = 'ProcessingStatus';

export default ProcessingStatus;