#!/usr/bin/env node
/**
 * Chequea todos los campos de un cliente
 * Uso: node check-customer-fields.js 201
 */

const https = require('https');

const SUPABASE_URL = "https://zjvpzqhbekxnwxdczpof.supabase.co";
const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InoqdnBzcWhiZWt4bnd4ZGN6cG9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NzEwMDc3MTAsImV4cCI6MTg5NjU4MzcxMH0.kxH7CzOjkWOsVVfBnCiJzT3_wvGOgA3pUOkz6TqKaWk";

const codCliente = process.argv[2] || "201";

async function makeRequest(path) {
  return new Promise((resolve, reject) => {
    const url = new URL(SUPABASE_URL + path);
    const options = {
      method: 'GET',
      headers: {
        'apikey': ANON_KEY,
        'Authorization': `Bearer ${ANON_KEY}`,
      },
    };

    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data || '[]') });
        } catch (e) {
          resolve({ status: res.statusCode, data });
        }
      });
    });

    req.on('error', reject);
    req.end();
  });
}

async function run() {
  console.log(`\n🔍 Buscando cliente con cod_cliente = ${codCliente}...\n`);

  const res = await makeRequest(`/rest/v1/customers?cod_cliente=eq.${codCliente}&select=*`);

  if (res.status !== 200) {
    console.error('❌ Error:', res.status, res.data);
    process.exit(1);
  }

  if (!res.data.length) {
    console.log(`❌ No encontrado cliente con cod_cliente = ${codCliente}`);
    process.exit(1);
  }

  const customer = res.data[0];
  console.log('📊 Cliente encontrado:\n');

  Object.entries(customer).forEach(([key, value]) => {
    const display = value === null ? '(null)' : value === '' ? '(vacío)' : value;
    console.log(`  ${key.padEnd(25)} : ${display}`);
  });

  console.log('\n');
}

run().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
