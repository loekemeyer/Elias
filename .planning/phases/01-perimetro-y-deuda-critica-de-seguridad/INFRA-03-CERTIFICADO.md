---
requirement: INFRA-03
status: CONFIRMADO — certificado vencido
date: 2026-07-21
severity: CRITICO (elevado desde MEDIO)
---

# INFRA-03 — El certificado TLS esta vencido. Confirmado.

## Veredicto

`tierravintage.com.ar` sirve un certificado TLS **vencido hace ~5 anos**. No es un artefacto de
diagnostico local. Confirmado desde dos rutas de red independientes.

## Evidencia

**Ruta 1 — PC del usuario (DISEÑO2-PC), handshake TLS directo:**
```
Subject : CN=tierravintage.com.ar
Issuer  : CN=The original certificate provided by the server is untrusted
Valido  : 12/7/2020 20:47:05  ->  12/7/2021 20:47:05
```
Este resultado por si solo NO era concluyente: el texto del issuer es caracteristico de un middlebox
que intercepta TLS (antivirus o proxy corporativo), asi que podia ser un artefacto de esa PC.

**Ruta 2 — WebFetch, red distinta, sin la interceptacion local:**
```
GET https://tierravintage.com.ar/script.js
-> certificate has expired
```

Dos rutas independientes, mismo diagnostico. El certificado del servidor esta vencido.

**Contexto adicional:** el navegador del usuario muestra "No es seguro" con el `https://` tachado
(captura del 2026-07-21), consistente con lo anterior.

## Por que esto se eleva a CRITICO

El roadmap original trataba INFRA-03 como el criterio de exito de menor prioridad de la fase, y
durante la planificacion se lo desacoplo explicitamente para que no bloqueara el cierre de la Phase 1.
**Ese juicio se hizo cuando el diagnostico era ambiguo. Ya no lo es, y el impacto de negocio cambia
la ecuacion.**

Los numeros de produccion:

| Metrica | Valor |
|---|---|
| Clientes con cuenta creada | 541 |
| Cuentas de auth | 539 |
| Productos cargados | 336 (286 activos, todos con imagen) |
| **Pedidos** | **1** |

El catalogo esta cargado, los clientes tienen credenciales, y nadie pide. La explicacion mas simple
es que todo visitante recibe una pantalla completa de advertencia de seguridad del navegador antes
de ver el sitio. En un sitio B2B que pide CUIT y PIN, eso destruye la conversion por dos vias:

1. **Abandono directo.** Un mayorista que ve "Tu conexion no es privada" cierra la pestana.
2. **Dano de segundo orden.** Los que igual entran aprenden a saltear advertencias de certificado
   — exactamente el reflejo que hace viable un ataque man-in-the-middle mas adelante.

**Hipotesis explicita, no verificada:** el certificado vencido es la causa principal de la falta de
uso del sitio, por encima de cualquier carencia funcional del frontend. Si es cierta, **renovarlo
tiene mas impacto que el port entero**, y cuesta ordenes de magnitud menos.

Como verificarla: renovar el certificado y medir si aparecen pedidos, antes de terminar el port.
Es barato y desambigua donde conviene poner el esfuerzo.

## Recomendacion de resecuenciamiento

Mover la renovacion del certificado al frente de todo, en paralelo con lo que queda de la Phase 1.
No depende de INFRA-01 (webroot) ni de nada del port. Es una tarea de panel de hosting.

## Pasos concretos (ejecutor: USUARIO)

El hosting es GoDaddy (`tierravintage.com.ar` -> 107.180.4.212). En las pestanas del usuario se vio
**SolidCP**, que es el panel de control probable.

1. Entrar al panel de hosting (SolidCP, o el panel de GoDaddy si el dominio se administra ahi).
2. Buscar la seccion SSL / Certificados.
3. Verificar si hay un certificado asociado al dominio y su fecha de vencimiento.
4. Segun lo que haya:
   - **Certificado comprado y vencido** -> renovarlo y reinstalarlo.
   - **Sin certificado** -> emitir uno. Let's Encrypt es gratis y muchos paneles (SolidCP incluido)
     lo integran con renovacion automatica. Es la opcion recomendada: el problema actual es
     precisamente que un certificado vencio y nadie lo renovo.
   - **Certificado valido en el panel pero el servidor sirve otro** -> el binding del sitio apunta
     al certificado equivocado. Corregir el binding.
5. Confirmar que la renovacion incluya **tanto** `tierravintage.com.ar` **como** `www.tierravintage.com.ar`.

## Como verificar que quedo bien

Ejecutar desde una red externa, no desde la PC con interceptacion TLS:

```
https://www.ssllabs.com/ssltest/analyze.html?d=tierravintage.com.ar
```

Criterio de cierre: grado **B o mejor**, sin el error "Certificate expired", y cadena completa.

Verificacion secundaria, ya sin advertencia:
```
https://tierravintage.com.ar/           -> carga sin warning del navegador
https://www.tierravintage.com.ar/       -> idem
```

## Efecto colateral util

Mientras el certificado este vencido, **Claude no puede hacer ninguna verificacion HTTP del sitio**:
ni WebFetch ni las herramientas HTTP validan contra un certificado invalido, y deshabilitar la
validacion esta bloqueado por politica del entorno (con razon: aceptar certificados invalidos
programaticamente es exactamente la practica que hace explotable un MITM).

Consecuencia practica: **INFRA-01 (determinar el webroot por HTTP) y SEC-03 (verificar que los
scripts no sean descargables) quedan bloqueados para Claude hasta que el certificado se renueve.**
Hoy dependen de que el usuario los pruebe manualmente desde su navegador.

Renovar el certificado desbloquea la verificacion automatizada del resto de la fase.
