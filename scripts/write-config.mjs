const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_PUBLISHABLE_KEY;
if (!url || !key) throw new Error('Supabase configuration is missing');
process.stdout.write(`window.ITA_CONFIG = ${JSON.stringify({ supabaseUrl: url, supabaseAnonKey: key })};\n`);

