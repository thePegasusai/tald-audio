import { MigrationInterface, QueryRunner } from "typeorm";

export class CreateAIModels1624500000002 implements MigrationInterface {
    public async up(queryRunner: QueryRunner): Promise<void> {
        // Create UUID extension if not exists
        await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);

        // Create ai_models table
        await queryRunner.query(`
            CREATE TABLE "ai_models" (
                "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                "model_id" VARCHAR NOT NULL UNIQUE,
                "version" VARCHAR NOT NULL,
                "model_type" VARCHAR NOT NULL,
                "accelerator" VARCHAR NOT NULL DEFAULT 'CPU',
                "parameters" JSONB NOT NULL DEFAULT '{}'::jsonb,
                "metrics" JSONB DEFAULT '{}'::jsonb,
                "latency_threshold_ms" DECIMAL NOT NULL DEFAULT 10.0,
                "active" BOOLEAN NOT NULL DEFAULT false,
                "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
                "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

                CONSTRAINT "CHK_ai_models_model_type" CHECK (
                    model_type IN ('AUDIO_ENHANCEMENT', 'ROOM_CORRECTION', 'SPATIAL_PROCESSING')
                ),
                CONSTRAINT "CHK_ai_models_accelerator" CHECK (
                    accelerator IN ('CPU', 'GPU', 'TPU')
                ),
                CONSTRAINT "CHK_ai_models_latency" CHECK (
                    latency_threshold_ms > 0
                )
            )
        `);

        // Create indexes for efficient querying
        await queryRunner.query(`
            CREATE INDEX "IDX_ai_models_model_type" ON "ai_models" ("model_type");
            CREATE INDEX "IDX_ai_models_version" ON "ai_models" ("version");
            CREATE INDEX "IDX_ai_models_active" ON "ai_models" ("active");
            CREATE INDEX "IDX_ai_models_latency" ON "ai_models" ("latency_threshold_ms");
            CREATE INDEX "IDX_ai_models_parameters" ON "ai_models" USING gin ("parameters");
        `);

        // Create trigger for automatic updated_at timestamp updates
        await queryRunner.query(`
            CREATE OR REPLACE FUNCTION update_ai_models_updated_at()
            RETURNS TRIGGER AS $$
            BEGIN
                NEW.updated_at = now();
                RETURN NEW;
            END;
            $$ language 'plpgsql';

            CREATE TRIGGER trigger_update_ai_models_timestamp
                BEFORE UPDATE ON "ai_models"
                FOR EACH ROW
                EXECUTE FUNCTION update_ai_models_updated_at();
        `);

        // Create partitioning for large deployments (optional, based on scale)
        await queryRunner.query(`
            CREATE OR REPLACE FUNCTION create_ai_models_partition()
            RETURNS TRIGGER AS $$
            DECLARE
                partition_date TEXT;
                partition_name TEXT;
            BEGIN
                partition_date := to_char(NEW.created_at, 'YYYY_MM');
                partition_name := 'ai_models_' || partition_date;
                
                IF NOT EXISTS (
                    SELECT 1
                    FROM pg_class
                    WHERE relname = partition_name
                ) THEN
                    EXECUTE format(
                        'CREATE TABLE IF NOT EXISTS %I PARTITION OF ai_models
                        FOR VALUES FROM (%L) TO (%L)',
                        partition_name,
                        date_trunc('month', NEW.created_at),
                        date_trunc('month', NEW.created_at + interval '1 month')
                    );
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trigger_ai_models_partition
                BEFORE INSERT ON "ai_models"
                FOR EACH ROW
                EXECUTE FUNCTION create_ai_models_partition();
        `);
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        // Drop triggers first
        await queryRunner.query(`
            DROP TRIGGER IF EXISTS trigger_ai_models_partition ON "ai_models";
            DROP FUNCTION IF EXISTS create_ai_models_partition();
            DROP TRIGGER IF EXISTS trigger_update_ai_models_timestamp ON "ai_models";
            DROP FUNCTION IF EXISTS update_ai_models_updated_at();
        `);

        // Drop indexes
        await queryRunner.query(`
            DROP INDEX IF EXISTS "IDX_ai_models_parameters";
            DROP INDEX IF EXISTS "IDX_ai_models_latency";
            DROP INDEX IF EXISTS "IDX_ai_models_active";
            DROP INDEX IF EXISTS "IDX_ai_models_version";
            DROP INDEX IF EXISTS "IDX_ai_models_model_type";
        `);

        // Drop the table
        await queryRunner.query(`DROP TABLE IF EXISTS "ai_models" CASCADE`);
    }
}