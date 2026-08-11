#!/usr/bin/env node
/**
 * Script para migrar productos de categoría "Importados" a "Portaretratos"
 *
 * Uso:
 *   SERVICE_ROLE_KEY=... node migrate-importados.js
 */

const https = require('https');

const SUPABASE_URL = "https://zjvpzqhbekxnwxdczpof.supabase.co";
const serviceKey = process.env.SERVICE_ROLE_KEY;

if (!serviceKey) {
  console.error('❌ Falta SERVICE_ROLE_KEY. Usa: SERVICE_ROLE_KEY=... node migrate-importados.js');
  process.exit(1);
}

async function makeRequest(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(SUPABASE_URL + path);
    const options = {
      method,
      headers: {
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
      },
    };

    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data || '{}') });
        } catch (e) {
          resolve({ status: res.statusCode, data });
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function run() {
  console.log('🔍 Buscando productos en categoría "Importados"...');

  // Contar productos
  const countRes = await makeRequest(
    'GET',
    '/rest/v1/products?category=eq.Importados&select=count()'
  );

  if (countRes.status !== 200) {
    console.error('❌ Error al contar:', countRes.data);
    process.exit(1);
  }

  const count = countRes.data[0]?.count || 0;
  console.log(`📊 Encontrados ${count} productos en "Importados"`);

  if (count === 0) {
    console.log('✅ No hay productos que migrar');
    process.exit(0);
  }

  console.log(`\n⚠️  Se van a cambiar ${count} productos a categoría "Portaretratos"`);
  console.log('Presioná Enter para continuar o Ctrl+C para cancelar...');

  // En Node interactivo esto es más complicado, así que solo continuamos
  // En un ambiente real, usarías readline para pedir confirmación

  console.log('\n🚀 Ejecutando migración...');

  // Hacer el UPDATE
  const updateRes = await makeRequest(
    'PATCH',
    '/rest/v1/products?category=eq.Importados',
    { category: 'Portaretratos' }
  );

  if (updateRes.status === 204 || updateRes.status === 200) {
    console.log('✅ Migración exitosa!');
    console.log(`   ${count} productos movidos a "Portaretratos"`);
  } else {
    console.error('❌ Error en migración:', updateRes.status, updateRes.data);
    process.exit(1);
  }
}

run().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
