import React, { useCallback, useEffect, useState } from 'react';
import styled from '@emotion/styled';
import { useForm, Controller } from 'react-hook-form';
import { debounce } from 'lodash';
import { ErrorBoundary } from 'react-error-boundary';

import { Profile, ProcessingQuality, AudioSettings } from '../../types/profile.types';
import { ProfileAPI } from '../../api/profile.api';
import Button from '../common/Button';

// Styled components with accessibility and theme integration
const FormContainer = styled.form`
  padding: ${({ theme }) => theme.spacing.xl};
  border-radius: 8px;
  background-color: ${({ theme }) => theme.colors.background.secondary};
  max-width: 800px;
  margin: 0 auto;

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const FormSection = styled.section`
  margin-bottom: ${({ theme }) => theme.spacing.xl};
  padding: ${({ theme }) => theme.spacing.lg};
  border: 1px solid ${({ theme }) => theme.colors.primary.main};
  border-radius: 4px;
`;

const FormField = styled.div`
  margin-bottom: ${({ theme }) => theme.spacing.md};
`;

const Label = styled.label`
  display: block;
  margin-bottom: ${({ theme }) => theme.spacing.sm};
  font-weight: ${({ theme }) => theme.typography.fontWeights.medium};
  color: ${({ theme }) => theme.colors.text.primary};
`;

const Input = styled.input`
  width: 100%;
  padding: ${({ theme }) => theme.spacing.md};
  border: 2px solid ${({ theme }) => theme.colors.primary.main};
  border-radius: 4px;
  background-color: ${({ theme }) => theme.colors.background.primary};
  color: ${({ theme }) => theme.colors.text.primary};
  font-size: ${({ theme }) => theme.typography.fontSizes.md};

  &:focus {
    outline: none;
    border-color: ${({ theme }) => theme.colors.primary.light};
    box-shadow: 0 0 0 2px ${({ theme }) => theme.colors.primary.main}40;
  }
`;

const Select = styled.select`
  width: 100%;
  padding: ${({ theme }) => theme.spacing.md};
  border: 2px solid ${({ theme }) => theme.colors.primary.main};
  border-radius: 4px;
  background-color: ${({ theme }) => theme.colors.background.primary};
  color: ${({ theme }) => theme.colors.text.primary};
  font-size: ${({ theme }) => theme.typography.fontSizes.md};
`;

const ErrorMessage = styled.span`
  color: ${({ theme }) => theme.colors.status.error};
  font-size: ${({ theme }) => theme.typography.fontSizes.sm};
  margin-top: ${({ theme }) => theme.spacing.xs};
  display: block;
`;

const ButtonGroup = styled.div`
  display: flex;
  justify-content: flex-end;
  gap: ${({ theme }) => theme.spacing.md};
  margin-top: ${({ theme }) => theme.spacing.xl};
`;

// Props interface
interface ProfileEditorProps {
  profile?: Profile;
  onSave: (profile: Profile) => void;
  onCancel: () => void;
  isLoading?: boolean;
}

// Form validation schema
const defaultValues: Partial<Profile> = {
  name: '',
  processingQuality: ProcessingQuality.Balanced,
  preferences: {
    theme: 'dark',
    language: 'en',
    notifications: true,
    autoSave: true
  },
  audioSettings: []
};

export const ProfileEditor: React.FC<ProfileEditorProps> = ({
  profile,
  onSave,
  onCancel,
  isLoading = false
}) => {
  const [validationError, setValidationError] = useState<string | null>(null);
  const { control, handleSubmit, reset, formState: { errors } } = useForm<Profile>({
    defaultValues: profile || defaultValues
  });

  // Reset form when profile changes
  useEffect(() => {
    if (profile) {
      reset(profile);
    }
  }, [profile, reset]);

  // Debounced validation
  const validateForm = useCallback(
    debounce(async (data: Profile) => {
      try {
        const api = new ProfileAPI(process.env.REACT_APP_API_URL || '');
        await api.validateProfile(data);
        setValidationError(null);
      } catch (error) {
        setValidationError((error as Error).message);
      }
    }, 500),
    []
  );

  const onSubmit = async (data: Profile) => {
    try {
      const api = new ProfileAPI(process.env.REACT_APP_API_URL || '');
      const savedProfile = profile
        ? await api.updateProfile(profile.id, data)
        : await api.createProfile(data);
      onSave(savedProfile);
    } catch (error) {
      setValidationError((error as Error).message);
    }
  };

  return (
    <ErrorBoundary
      fallback={<div>Something went wrong. Please try again.</div>}
      onError={(error) => console.error('ProfileEditor Error:', error)}
    >
      <FormContainer onSubmit={handleSubmit(onSubmit)} aria-label="Profile Editor">
        <FormSection>
          <FormField>
            <Controller
              name="name"
              control={control}
              rules={{ required: 'Profile name is required' }}
              render={({ field }) => (
                <>
                  <Label htmlFor="name">Profile Name</Label>
                  <Input
                    id="name"
                    type="text"
                    aria-invalid={!!errors.name}
                    aria-describedby={errors.name ? 'name-error' : undefined}
                    {...field}
                  />
                  {errors.name && (
                    <ErrorMessage id="name-error" role="alert">
                      {errors.name.message}
                    </ErrorMessage>
                  )}
                </>
              )}
            />
          </FormField>

          <FormField>
            <Controller
              name="processingQuality"
              control={control}
              render={({ field }) => (
                <>
                  <Label htmlFor="processingQuality">Processing Quality</Label>
                  <Select
                    id="processingQuality"
                    {...field}
                  >
                    <option value={ProcessingQuality.Maximum}>Maximum Quality</option>
                    <option value={ProcessingQuality.Balanced}>Balanced</option>
                    <option value={ProcessingQuality.PowerSaver}>Power Saver</option>
                  </Select>
                </>
              )}
            />
          </FormField>
        </FormSection>

        <FormSection>
          <h3>Audio Settings</h3>
          {/* Audio settings form fields would go here */}
        </FormSection>

        {validationError && (
          <ErrorMessage role="alert">{validationError}</ErrorMessage>
        )}

        <ButtonGroup>
          <Button
            type="button"
            variant="secondary"
            onClick={onCancel}
            disabled={isLoading}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            variant="primary"
            loading={isLoading}
            disabled={isLoading}
          >
            {profile ? 'Update Profile' : 'Create Profile'}
          </Button>
        </ButtonGroup>
      </FormContainer>
    </ErrorBoundary>
  );
};

export default ProfileEditor;