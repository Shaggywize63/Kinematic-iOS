const { createClient } = require('@supabase/supabase-js');
const dotenv = require('dotenv');
const path = require('path');

// Try to find .env in various places
dotenv.config({ path: '/Users/sagbharg/Desktop/Kinematic Code/Kinematic/.env' });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing Supabase credentials in .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkForms() {
  const { data: forms, error: fErr } = await supabase
    .from('builder_forms')
    .select('*, builder_questions(*)');

  if (fErr) {
    console.error('Error fetching forms:', fErr);
    return;
  }

  console.log('--- FORMS IN DATABASE ---');
  forms.forEach(f => {
    console.log(`\nFORM: ${f.title} (ID: ${f.id})`);
    console.log(`DESCRIPTION: ${f.description}`);
    console.log(`ACTIVITY_ID: ${f.activity_id}`);
    console.log('QUESTIONS:');
    f.builder_questions?.sort((a,b) => a.q_order - b.q_order).forEach(q => {
      console.log(`  - [${q.qtype}] ${q.label} (Key: ${q.id})`);
      if (q.options?.length) {
        console.log(`    Options: ${JSON.stringify(q.options)}`);
      }
      if (q.depends_on_id) {
        console.log(`    Depends on: ${q.depends_on_id} == ${q.depends_on_value}`);
      }
    });
  });
}

checkForms();
