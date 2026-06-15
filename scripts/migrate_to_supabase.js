const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

const connectionString = 'postgresql://postgres:Alif_hakimie00@db.czpwukxezggtjxzneeje.supabase.co:5432/postgres';

async function run() {
  const client = new Client({ connectionString });

  try {
    console.log('Connecting to Supabase PostgreSQL...');
    await client.connect();
    console.log('Connected successfully.');

    // Run schema migration
    const rootDir = path.resolve(__dirname, '..');
    const schemaPath = path.join(rootDir, 'supabase', 'migrations', '001_init_schema.sql');
    const schemaSql = fs.readFileSync(schemaPath, 'utf8');
    console.log('Running schema migration...');
    await client.query(schemaSql);
    console.log('Schema migration completed.');

    // Run seed data
    const seedPath = path.join(rootDir, 'supabase', 'seed.sql');
    const seedSql = fs.readFileSync(seedPath, 'utf8');
    console.log('Running seed data...');
    await client.query(seedSql);
    console.log('Seed data completed.');

    // Verify tables
    const tables = await client.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name"
    );
    console.log('\nTables created:');
    tables.rows.forEach(r => console.log(`  - ${r.table_name}`));

    console.log('\nMigration completed successfully!');
  } catch (err) {
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

run();
