import { MigrationInterface, QueryRunner, Table, TableIndex } from "typeorm";

export class CreateAudioSettings1624500000001 implements MigrationInterface {
    public async up(queryRunner: QueryRunner): Promise<void> {
        // Create uuid-ossp extension if not exists
        await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);

        // Create ENUM type for processing quality
        await queryRunner.query(`
            CREATE TYPE processing_quality_enum AS ENUM (
                'maximum',
                'balanced',
                'power_saver'
            )
        `);

        // Create JSON validation functions
        await queryRunner.query(`
            CREATE OR REPLACE FUNCTION validate_dsp_json(settings jsonb) 
            RETURNS boolean AS $$
            BEGIN
                RETURN (
                    settings ? 'equalizer' AND
                    settings ? 'compression' AND
                    settings ? 'noise_reduction'
                );
            END;
            $$ LANGUAGE plpgsql;

            CREATE OR REPLACE FUNCTION validate_ai_json(settings jsonb)
            RETURNS boolean AS $$
            BEGIN
                RETURN (
                    settings ? 'enhancement_level' AND
                    settings ? 'model_version' AND
                    settings ? 'processing_mode'
                );
            END;
            $$ LANGUAGE plpgsql;

            CREATE OR REPLACE FUNCTION validate_spatial_json(settings jsonb)
            RETURNS boolean AS $$
            BEGIN
                RETURN (
                    settings ? 'room_size' AND
                    settings ? 'head_tracking' AND
                    settings ? 'hrtf_profile'
                );
            END;
            $$ LANGUAGE plpgsql;
        `);

        // Create audio_settings table
        await queryRunner.createTable(new Table({
            name: "audio_settings",
            columns: [
                {
                    name: "id",
                    type: "uuid",
                    isPrimary: true,
                    default: "uuid_generate_v4()",
                    comment: "Unique identifier for audio settings"
                },
                {
                    name: "profile_id",
                    type: "uuid",
                    isNullable: false,
                    comment: "Reference to user profile"
                },
                {
                    name: "sample_rate",
                    type: "integer",
                    isNullable: false,
                    default: 48000,
                    comment: "Audio sample rate in Hz (8000-192000)"
                },
                {
                    name: "bit_depth",
                    type: "integer",
                    isNullable: false,
                    default: 24,
                    comment: "Audio bit depth (16, 24, or 32)"
                },
                {
                    name: "processing_quality",
                    type: "processing_quality_enum",
                    isNullable: false,
                    default: "'balanced'",
                    comment: "Overall processing quality setting"
                },
                {
                    name: "dsp_settings",
                    type: "jsonb",
                    isNullable: false,
                    default: "'{}'::jsonb",
                    comment: "DSP configuration parameters"
                },
                {
                    name: "ai_settings",
                    type: "jsonb",
                    isNullable: false,
                    default: "'{}'::jsonb",
                    comment: "AI enhancement parameters"
                },
                {
                    name: "spatial_settings",
                    type: "jsonb",
                    isNullable: false,
                    default: "'{}'::jsonb",
                    comment: "Spatial audio configuration"
                },
                {
                    name: "active",
                    type: "boolean",
                    isNullable: false,
                    default: false,
                    comment: "Whether this is the active settings profile"
                },
                {
                    name: "created_at",
                    type: "timestamp with time zone",
                    isNullable: false,
                    default: "now()",
                    comment: "Timestamp of settings creation"
                },
                {
                    name: "updated_at",
                    type: "timestamp with time zone",
                    isNullable: false,
                    default: "now()",
                    comment: "Timestamp of last settings update"
                }
            ],
            foreignKeys: [
                {
                    columnNames: ["profile_id"],
                    referencedTableName: "profiles",
                    referencedColumnNames: ["id"],
                    onDelete: "CASCADE"
                }
            ]
        }), true);

        // Add CHECK constraints
        await queryRunner.query(`
            ALTER TABLE audio_settings
            ADD CONSTRAINT check_sample_rate 
            CHECK (sample_rate BETWEEN 8000 AND 192000);

            ALTER TABLE audio_settings
            ADD CONSTRAINT check_bit_depth
            CHECK (bit_depth IN (16, 24, 32));

            ALTER TABLE audio_settings
            ADD CONSTRAINT check_dsp_settings
            CHECK (validate_dsp_json(dsp_settings));

            ALTER TABLE audio_settings
            ADD CONSTRAINT check_ai_settings
            CHECK (validate_ai_json(ai_settings));

            ALTER TABLE audio_settings
            ADD CONSTRAINT check_spatial_settings
            CHECK (validate_spatial_json(spatial_settings));
        `);

        // Create indexes
        await queryRunner.createIndices("audio_settings", [
            new TableIndex({
                name: "IDX_audio_settings_profile_id",
                columnNames: ["profile_id"]
            }),
            new TableIndex({
                name: "IDX_audio_settings_active",
                columnNames: ["active"],
                where: "active = true"
            }),
            new TableIndex({
                name: "IDX_audio_settings_profile_active",
                columnNames: ["profile_id", "active"]
            }),
            new TableIndex({
                name: "IDX_audio_settings_dsp",
                columnNames: ["dsp_settings"],
                using: "GIN"
            }),
            new TableIndex({
                name: "IDX_audio_settings_ai",
                columnNames: ["ai_settings"],
                using: "GIN"
            }),
            new TableIndex({
                name: "IDX_audio_settings_spatial",
                columnNames: ["spatial_settings"],
                using: "GIN"
            })
        ]);

        // Create updated_at trigger
        await queryRunner.query(`
            CREATE TRIGGER set_updated_at
            BEFORE UPDATE ON audio_settings
            FOR EACH ROW
            EXECUTE FUNCTION trigger_set_updated_at();
        `);
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        // Drop triggers
        await queryRunner.query(`DROP TRIGGER IF EXISTS set_updated_at ON audio_settings`);

        // Drop indexes
        await queryRunner.dropIndex("audio_settings", "IDX_audio_settings_profile_id");
        await queryRunner.dropIndex("audio_settings", "IDX_audio_settings_active");
        await queryRunner.dropIndex("audio_settings", "IDX_audio_settings_profile_active");
        await queryRunner.dropIndex("audio_settings", "IDX_audio_settings_dsp");
        await queryRunner.dropIndex("audio_settings", "IDX_audio_settings_ai");
        await queryRunner.dropIndex("audio_settings", "IDX_audio_settings_spatial");

        // Drop CHECK constraints
        await queryRunner.query(`
            ALTER TABLE audio_settings
            DROP CONSTRAINT IF EXISTS check_sample_rate,
            DROP CONSTRAINT IF EXISTS check_bit_depth,
            DROP CONSTRAINT IF EXISTS check_dsp_settings,
            DROP CONSTRAINT IF EXISTS check_ai_settings,
            DROP CONSTRAINT IF EXISTS check_spatial_settings
        `);

        // Drop validation functions
        await queryRunner.query(`
            DROP FUNCTION IF EXISTS validate_dsp_json;
            DROP FUNCTION IF EXISTS validate_ai_json;
            DROP FUNCTION IF EXISTS validate_spatial_json;
        `);

        // Drop ENUM type
        await queryRunner.query(`DROP TYPE IF EXISTS processing_quality_enum`);

        // Drop table
        await queryRunner.dropTable("audio_settings", true);
    }
}