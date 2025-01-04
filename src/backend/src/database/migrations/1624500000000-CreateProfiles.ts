import { MigrationInterface, QueryRunner, Table, TableIndex } from "typeorm";

export class CreateProfiles1624500000000 implements MigrationInterface {
    name = 'CreateProfiles1624500000000';

    public async up(queryRunner: QueryRunner): Promise<void> {
        // Enable UUID generation if not already enabled
        await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);

        // Create profiles table
        await queryRunner.createTable(
            new Table({
                name: "profiles",
                columns: [
                    {
                        name: "id",
                        type: "uuid",
                        isPrimary: true,
                        default: "uuid_generate_v4()",
                    },
                    {
                        name: "userId",
                        type: "varchar",
                        length: "255",
                        isNullable: false,
                    },
                    {
                        name: "name",
                        type: "varchar",
                        length: "255",
                        isNullable: false,
                    },
                    {
                        name: "preferences",
                        type: "jsonb",
                        isNullable: true,
                    },
                    {
                        name: "isDefault",
                        type: "boolean",
                        default: false,
                        isNullable: false,
                    },
                    {
                        name: "createdAt",
                        type: "timestamp with time zone",
                        default: "CURRENT_TIMESTAMP",
                        isNullable: false,
                    },
                    {
                        name: "updatedAt",
                        type: "timestamp with time zone",
                        default: "CURRENT_TIMESTAMP",
                        isNullable: false,
                    },
                ],
            }),
            true
        );

        // Create unique constraint for userId + name combination
        await queryRunner.createIndex(
            "profiles",
            new TableIndex({
                name: "UQ_profiles_user_id_name",
                columnNames: ["userId", "name"],
                isUnique: true,
            })
        );

        // Create index for userId lookups
        await queryRunner.createIndex(
            "profiles",
            new TableIndex({
                name: "IDX_profiles_user_id",
                columnNames: ["userId"],
            })
        );

        // Create index for time-based partitioning
        await queryRunner.createIndex(
            "profiles",
            new TableIndex({
                name: "IDX_profiles_created_at",
                columnNames: ["createdAt"],
            })
        );

        // Create partial index for default profiles
        await queryRunner.createIndex(
            "profiles",
            new TableIndex({
                name: "IDX_profiles_is_default",
                columnNames: ["isDefault"],
                where: `"isDefault" = true`,
            })
        );

        // Create GIN index for JSONB preferences queries
        await queryRunner.createIndex(
            "profiles",
            new TableIndex({
                name: "IDX_profiles_preferences",
                columnNames: ["preferences"],
                using: "GIN",
            })
        );

        // Create function for automatic timestamp updates
        await queryRunner.query(`
            CREATE OR REPLACE FUNCTION update_updated_at_column()
            RETURNS TRIGGER AS $$
            BEGIN
                NEW.updatedAt = CURRENT_TIMESTAMP;
                RETURN NEW;
            END;
            $$ language 'plpgsql';
        `);

        // Create trigger for automatic timestamp updates
        await queryRunner.query(`
            CREATE TRIGGER set_timestamp
                BEFORE UPDATE ON profiles
                FOR EACH ROW
                EXECUTE FUNCTION update_updated_at_column();
        `);

        // Create time-based partitioning function
        await queryRunner.query(`
            CREATE OR REPLACE FUNCTION create_profiles_partition()
            RETURNS void AS $$
            DECLARE
                partition_date text;
                partition_name text;
                start_date timestamp;
                end_date timestamp;
            BEGIN
                partition_date := to_char(date_trunc('month', CURRENT_DATE), 'YYYY_MM');
                partition_name := 'profiles_' || partition_date;
                start_date := date_trunc('month', CURRENT_DATE);
                end_date := start_date + interval '1 month';
                
                EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF profiles
                    FOR VALUES FROM (%L) TO (%L)',
                    partition_name, start_date, end_date);
            END;
            $$ LANGUAGE plpgsql;
        `);
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        // Drop indices in reverse order
        await queryRunner.dropIndex("profiles", "IDX_profiles_preferences");
        await queryRunner.dropIndex("profiles", "IDX_profiles_is_default");
        await queryRunner.dropIndex("profiles", "IDX_profiles_created_at");
        await queryRunner.dropIndex("profiles", "IDX_profiles_user_id");
        await queryRunner.dropIndex("profiles", "UQ_profiles_user_id_name");

        // Drop trigger and function
        await queryRunner.query(`DROP TRIGGER IF EXISTS set_timestamp ON profiles`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS update_updated_at_column()`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS create_profiles_partition()`);

        // Drop the profiles table
        await queryRunner.dropTable("profiles", true);
    }
}