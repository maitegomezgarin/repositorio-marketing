// =====================================================================
// app.js — Tablero EcoBottle AR
// =====================================================================
// Lee las tablas del data warehouse (los CSV de la carpeta dw/) y calcula
// los KPIs con las mismas definiciones de sql/03_consultas.sql.
// =====================================================================

const RUTA_DW = '../dw/';
const TABLAS = [
    'dim_channel', 'dim_province', 'dim_product',
    'fact_sales', 'fact_sales_item', 'fact_web_session', 'fact_nps', 'fact_shipment'
];

const datos = {};      // tablas cargadas, una por nombre
const graficos = {};   // gráficos de Chart.js, uno por id de canvas

const MESES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
const AZUL_MARINO = '#1b2f5b';
const CELESTE = '#4aa8e0';
const CELESTE_CLARO = '#c4dff2';
const ROJO = '#c2453d';
const COLOR_CANAL = { ONLINE: CELESTE, OFFLINE: AZUL_MARINO };

const formatoEntero = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 0 });
const formatoDecimal = new Intl.NumberFormat('es-AR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });


// ---------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------

// Lee un CSV de dw/ y devuelve una lista de filas (objetos)
function cargarTabla(nombre) {
    return new Promise((resolver, rechazar) => {
        Papa.parse(RUTA_DW + nombre + '.csv', {
            download: true,
            header: true,
            dynamicTyping: true,
            skipEmptyLines: true,
            complete: (resultado) => resolver(resultado.data),
            error: rechazar
        });
    });
}

// date_key (20240131) -> mes (202401)
function mesDe(dateKey) {
    return Math.floor(dateKey / 100);
}

// date_key (20240131) -> trimestre (20241)
function trimestreDe(dateKey) {
    const anio = Math.floor(dateKey / 10000);
    const mes = Math.floor(dateKey / 100) % 100;
    return anio * 10 + Math.ceil(mes / 3);
}

// 202401 -> "Ene 2024"
function nombreMes(mes) {
    return MESES[(mes % 100) - 1] + ' ' + Math.floor(mes / 100);
}

// 20241 -> "T1 2024"
function nombreTrimestre(trimestre) {
    return 'T' + (trimestre % 10) + ' ' + Math.floor(trimestre / 10);
}

// Todos los meses entre dos date_key (incluidos)
function mesesEntre(desde, hasta) {
    const meses = [];
    let mes = mesDe(desde);
    while (mes <= mesDe(hasta)) {
        meses.push(mes);
        mes = (mes % 100 === 12) ? mes + 89 : mes + 1;   // 202412 -> 202501
    }
    return meses;
}

// "2024-01-31" -> 20240131
function inputAFecha(valor) {
    return parseInt(valor.replaceAll('-', ''), 10);
}

function dinero(valor) {
    return '$' + formatoEntero.format(valor);
}

function millones(valor) {
    return '$' + formatoDecimal.format(valor / 1e6) + ' M';
}

function miles(valor) {
    return formatoDecimal.format(valor / 1e3) + ' K';
}

function sumar(filas, campo) {
    return filas.reduce((total, fila) => total + fila[campo], 0);
}

// Crea un gráfico o lo reemplaza si ya existía
function dibujar(id, configuracion) {
    if (graficos[id]) {
        graficos[id].destroy();
    }
    configuracion.options = Object.assign({
        responsive: true,
        maintainAspectRatio: false,
        locale: 'es-AR',
        interaction: { mode: 'index', intersect: false }
    }, configuracion.options);
    graficos[id] = new Chart(document.getElementById(id), configuracion);
}

function escribir(id, texto) {
    document.getElementById(id).textContent = texto;
}


// ---------------------------------------------------------------------
// Filtros
// ---------------------------------------------------------------------

function llenarSelect(id, opciones, textoTodos) {
    const select = document.getElementById(id);
    select.innerHTML = '';
    if (textoTodos) {
        select.add(new Option(textoTodos, ''));
    }
    opciones.forEach(([valor, texto]) => select.add(new Option(texto, valor)));
}

function prepararFiltros() {
    llenarSelect('f-canal', datos.dim_channel.map(c => [c.channel_key, c.name + ' (' + c.code + ')']), 'Todos');
    llenarSelect('f-provincia', datos.dim_province.map(p => [p.province_key, p.name]), 'Todas');
    llenarSelect('f-producto', datos.dim_product.map(p => [p.product_key, p.name]), 'Todos');
    llenarSelect('f-top', datos.dim_product.map((p, i) => [i + 1, String(i + 1)]));
    document.getElementById('f-top').value = String(datos.dim_product.length);

    ['f-desde', 'f-hasta', 'f-canal', 'f-provincia', 'f-producto', 'f-top'].forEach(id => {
        document.getElementById(id).addEventListener('change', actualizar);
    });

    document.getElementById('f-limpiar').addEventListener('click', () => {
        document.getElementById('f-desde').value = '2024-01-01';
        document.getElementById('f-hasta').value = '2025-09-30';
        ['f-canal', 'f-provincia', 'f-producto'].forEach(id => { document.getElementById(id).value = ''; });
        actualizar();
    });
}

function leerFiltros() {
    const numeroONulo = (id) => {
        const valor = document.getElementById(id).value;
        return valor === '' ? null : Number(valor);
    };
    let desde = inputAFecha(document.getElementById('f-desde').value || '2024-01-01');
    let hasta = inputAFecha(document.getElementById('f-hasta').value || '2025-09-30');
    if (desde > hasta) {
        [desde, hasta] = [hasta, desde];
    }
    return {
        desde,
        hasta,
        canal: numeroONulo('f-canal'),
        provincia: numeroONulo('f-provincia'),
        producto: numeroONulo('f-producto'),
        top: Number(document.getElementById('f-top').value)
    };
}

function pasaFecha(fila, f) {
    return fila.date_key >= f.desde && fila.date_key <= f.hasta;
}

function pasaCanal(fila, f) {
    return f.canal === null || fila.channel_key === f.canal;
}

function pasaProvincia(fila, f) {
    return f.provincia === null || fila.province_key === f.provincia;
}

function pasaProducto(fila, f) {
    return f.producto === null || fila.product_key === f.producto;
}


// ---------------------------------------------------------------------
// Vistas
// ---------------------------------------------------------------------

// Ventas: SUM(total_amount) de los pedidos PAID o FULFILLED (is_sale)
// Ticket Promedio: SUM(total_amount) / COUNT(*) con el mismo filtro
function vistaVentas(f, meses) {
    const ventas = datos.fact_sales.filter(v => v.is_sale && pasaFecha(v, f) && pasaCanal(v, f) && pasaProvincia(v, f));
    const total = sumar(ventas, 'total_amount');

    escribir('kpi-ventas', millones(total));
    escribir('kpi-ventas-detalle', dinero(total) + ' · ' + formatoEntero.format(ventas.length) + ' pedidos');
    escribir('kpi-ticket', ventas.length ? '$' + miles(total / ventas.length) : '—');
    escribir('kpi-ticket-detalle', ventas.length ? dinero(total / ventas.length) + ' por pedido' : 'Sin pedidos');

    const canales = datos.dim_channel.filter(c => f.canal === null || c.channel_key === f.canal);
    dibujar('g-ventas', {
        type: 'line',
        data: {
            labels: meses.map(nombreMes),
            datasets: canales.map(c => ({
                label: c.code,
                data: meses.map(m => sumar(ventas.filter(v => v.channel_key === c.channel_key && mesDe(v.date_key) === m), 'total_amount')),
                borderColor: COLOR_CANAL[c.code],
                backgroundColor: COLOR_CANAL[c.code],
                tension: 0.25
            }))
        },
        options: {
            scales: { y: { beginAtZero: true, ticks: { callback: (v) => millones(v) } } },
            plugins: { tooltip: { callbacks: { label: (c) => c.dataset.label + ': ' + dinero(c.parsed.y) } } }
        }
    });
}

// Usuarios Activos: COUNT(DISTINCT customer_id), o session_id si es anónimo
// (en el DW es COUNT(DISTINCT active_user_id))
function vistaUsuarios(f, meses) {
    const sesiones = datos.fact_web_session.filter(s => pasaFecha(s, f) && pasaCanal(s, f));
    const usuarios = new Set(sesiones.map(s => s.active_user_id));

    escribir('kpi-usuarios', sesiones.length ? miles(usuarios.size) : '—');
    escribir('kpi-usuarios-detalle', sesiones.length
        ? formatoEntero.format(usuarios.size) + ' usuarios · ' + formatoEntero.format(sesiones.length) + ' sesiones'
        : 'Sin visitas: la web es del canal ONLINE');

    const porMes = new Map(meses.map(m => [m, new Set()]));
    sesiones.forEach(s => porMes.get(mesDe(s.date_key)).add(s.active_user_id));

    dibujar('g-usuarios', {
        type: 'line',
        data: {
            labels: meses.map(nombreMes),
            datasets: [{
                label: 'Usuarios activos',
                data: meses.map(m => porMes.get(m).size),
                borderColor: COLOR_CANAL.ONLINE,
                backgroundColor: COLOR_CANAL.ONLINE,
                tension: 0.25
            }]
        },
        options: {
            scales: { y: { beginAtZero: true } },
            plugins: { legend: { display: false } }
        }
    });
}

// NPS: (% puntajes 9-10 - % puntajes 0-6) * 100 = promedio de nps_value
function vistaNps(f, meses) {
    const respuestas = datos.fact_nps.filter(n => pasaFecha(n, f) && pasaCanal(n, f));
    const nps = respuestas.length ? sumar(respuestas, 'nps_value') / respuestas.length : null;
    const promotores = respuestas.filter(n => n.nps_category === 'Promotor').length;
    const detractores = respuestas.filter(n => n.nps_category === 'Detractor').length;

    escribir('kpi-nps', nps === null ? '—' : formatoDecimal.format(nps));
    escribir('kpi-nps-detalle', respuestas.length
        ? formatoEntero.format(respuestas.length) + ' respuestas · ' + formatoEntero.format(promotores) + ' promotores · ' + formatoEntero.format(detractores) + ' detractores'
        : 'Sin respuestas');

    const porMes = meses.map(m => {
        const delMes = respuestas.filter(n => mesDe(n.date_key) === m);
        return delMes.length ? Math.round(sumar(delMes, 'nps_value') / delMes.length * 10) / 10 : null;
    });

    dibujar('g-nps', {
        type: 'line',
        data: {
            labels: meses.map(nombreMes),
            datasets: [{
                label: 'NPS',
                data: porMes,
                borderColor: AZUL_MARINO,
                backgroundColor: AZUL_MARINO,
                tension: 0.25
            }]
        },
        options: {
            scales: { y: { suggestedMin: 0, suggestedMax: 60 } },
            plugins: { legend: { display: false } }
        }
    });
}

// Ventas por provincia: total_amount agrupado por la provincia de la dirección de envío
function vistaProvincias(f) {
    const ventas = datos.fact_sales.filter(v => v.is_sale && pasaFecha(v, f) && pasaCanal(v, f));
    const filas = datos.dim_province
        .map(p => ({
            key: p.province_key,
            nombre: p.name,
            total: sumar(ventas.filter(v => v.province_key === p.province_key), 'total_amount')
        }))
        .sort((a, b) => b.total - a.total);
    const totalGeneral = sumar(filas, 'total');

    dibujar('g-provincias', {
        type: 'bar',
        data: {
            labels: filas.map(p => p.nombre),
            datasets: [{
                label: 'Ventas',
                data: filas.map(p => p.total),
                backgroundColor: filas.map(p => (f.provincia === null || p.key === f.provincia) ? AZUL_MARINO : CELESTE_CLARO)
            }]
        },
        options: {
            indexAxis: 'y',
            scales: { x: { beginAtZero: true, ticks: { callback: (v) => millones(v) } } },
            plugins: {
                legend: { display: false },
                tooltip: {
                    callbacks: {
                        label: (c) => dinero(c.parsed.x) + (totalGeneral ? ' · ' + formatoDecimal.format(c.parsed.x / totalGeneral * 100) + '%' : '')
                    }
                }
            }
        }
    });
}

// Ranking mensual por producto: line_total agrupado por producto y mes
function vistaRanking(f) {
    const items = datos.fact_sales_item.filter(i => i.is_sale && pasaFecha(i, f) && pasaCanal(i, f) && pasaProvincia(i, f) && pasaProducto(i, f));
    const nombres = new Map(datos.dim_product.map(p => [p.product_key, p.name]));

    const porMes = new Map();
    items.forEach(i => {
        const mes = mesDe(i.date_key);
        if (!porMes.has(mes)) {
            porMes.set(mes, new Map());
        }
        const productos = porMes.get(mes);
        productos.set(i.product_key, (productos.get(i.product_key) || 0) + i.line_total);
    });

    const encabezado = document.getElementById('ranking-encabezado');
    const cuerpo = document.getElementById('ranking-cuerpo');
    encabezado.innerHTML = '';
    cuerpo.innerHTML = '';

    const filaEncabezado = encabezado.insertRow();
    ['Mes'].concat(Array.from({ length: f.top }, (_, i) => (i + 1) + '°')).forEach(texto => {
        const th = document.createElement('th');
        th.textContent = texto;
        filaEncabezado.appendChild(th);
    });

    const meses = Array.from(porMes.keys()).sort((a, b) => b - a);   // del más reciente al más antiguo
    if (meses.length === 0) {
        const celda = cuerpo.insertRow().insertCell();
        celda.colSpan = f.top + 1;
        celda.textContent = 'Sin ventas para los filtros elegidos';
        return;
    }

    meses.forEach(mes => {
        const fila = cuerpo.insertRow();
        fila.insertCell().textContent = nombreMes(mes);
        const ranking = Array.from(porMes.get(mes).entries()).sort((a, b) => b[1] - a[1]);
        for (let i = 0; i < f.top; i++) {
            const celda = fila.insertCell();
            if (ranking[i]) {
                celda.textContent = nombres.get(ranking[i][0]);
                const monto = document.createElement('span');
                monto.className = 'monto';
                monto.textContent = dinero(ranking[i][1]);
                celda.appendChild(monto);
            } else {
                celda.textContent = '—';
            }
        }
    });
}

// Meta 1: crecer 15% las ventas en Córdoba (variación contra el trimestre anterior)
function vistaMetaCordoba(f) {
    const cordoba = datos.dim_province.find(p => p.name === 'Córdoba').province_key;
    const ventas = datos.fact_sales.filter(v => v.is_sale && v.province_key === cordoba && pasaCanal(v, f));

    const porTrimestre = new Map();
    ventas.forEach(v => {
        const t = trimestreDe(v.date_key);
        porTrimestre.set(t, (porTrimestre.get(t) || 0) + v.total_amount);
    });
    const trimestres = Array.from(porTrimestre.keys()).sort((a, b) => a - b);
    const montos = trimestres.map(t => porTrimestre.get(t));
    const variaciones = montos.map((m, i) => i === 0 ? null : (m / montos[i - 1] - 1) * 100);

    dibujar('g-cordoba', {
        type: 'bar',
        data: {
            labels: trimestres.map(nombreTrimestre),
            datasets: [{
                label: 'Ventas en Córdoba',
                data: montos,
                backgroundColor: variaciones.map(v => v === null ? CELESTE_CLARO : (v >= 15 ? AZUL_MARINO : ROJO))
            }]
        },
        options: {
            scales: { y: { beginAtZero: true, ticks: { callback: (v) => millones(v) } } },
            plugins: {
                legend: { display: false },
                tooltip: {
                    callbacks: {
                        label: (c) => dinero(c.parsed.y),
                        afterLabel: (c) => variaciones[c.dataIndex] === null ? '' : 'Variación: ' + formatoDecimal.format(variaciones[c.dataIndex]) + '%'
                    }
                }
            }
        }
    });

    const ultima = variaciones[variaciones.length - 1];
    escribir('meta-cordoba', ultima === null || ultima === undefined
        ? 'Sin datos suficientes.'
        : 'Último trimestre (' + nombreTrimestre(trimestres[trimestres.length - 1]) + '): ' + formatoDecimal.format(ultima) + '% contra el anterior. Meta: +15%. '
          + (ultima >= 15 ? 'Meta cumplida.' : 'Meta no alcanzada.') + ' Azul marino: creció 15% o más; rojo: no llegó.');
}

// Meta 2: reducir los tiempos de entrega en Mendoza (días de la compra a la entrega)
function vistaMetaMendoza(f) {
    const mendoza = datos.dim_province.find(p => p.name === 'Mendoza').province_key;
    const entregados = datos.fact_shipment.filter(s => s.status === 'DELIVERED' && pasaCanal(s, f));

    const trimestres = Array.from(new Set(entregados.map(s => trimestreDe(s.date_key)))).sort((a, b) => a - b);
    const promedio = (filas) => filas.length ? Math.round(sumar(filas, 'days_to_delivery') / filas.length * 100) / 100 : null;
    const serieMendoza = trimestres.map(t => promedio(entregados.filter(s => s.province_key === mendoza && trimestreDe(s.date_key) === t)));
    const serieResto = trimestres.map(t => promedio(entregados.filter(s => s.province_key !== mendoza && trimestreDe(s.date_key) === t)));

    dibujar('g-mendoza', {
        type: 'line',
        data: {
            labels: trimestres.map(nombreTrimestre),
            datasets: [
                { label: 'Mendoza', data: serieMendoza, borderColor: AZUL_MARINO, backgroundColor: AZUL_MARINO, tension: 0.25 },
                { label: 'Resto de las provincias', data: serieResto, borderColor: CELESTE, backgroundColor: CELESTE, tension: 0.25 }
            ]
        },
        options: {
            scales: { y: { beginAtZero: true, title: { display: true, text: 'Días' } } },
            plugins: { tooltip: { callbacks: { label: (c) => c.dataset.label + ': ' + formatoDecimal.format(c.parsed.y) + ' días' } } }
        }
    });

    const conDatos = serieMendoza.filter(v => v !== null);
    escribir('meta-mendoza', conDatos.length < 2
        ? 'Sin datos suficientes.'
        : 'Mendoza pasó de ' + formatoDecimal.format(conDatos[conDatos.length - 2]) + ' a ' + formatoDecimal.format(conDatos[conDatos.length - 1])
          + ' días en el último trimestre (' + nombreTrimestre(trimestres[trimestres.length - 1]) + ').');
}


// ---------------------------------------------------------------------
// Inicio
// ---------------------------------------------------------------------

function actualizar() {
    const f = leerFiltros();
    const meses = mesesEntre(f.desde, f.hasta);
    vistaVentas(f, meses);
    vistaUsuarios(f, meses);
    vistaNps(f, meses);
    vistaProvincias(f);
    vistaRanking(f);
    vistaMetaCordoba(f);
    vistaMetaMendoza(f);
}

async function iniciar() {
    try {
        const tablas = await Promise.all(TABLAS.map(cargarTabla));
        TABLAS.forEach((nombre, i) => { datos[nombre] = tablas[i]; });
        prepararFiltros();
        document.getElementById('estado').hidden = true;
        document.getElementById('tablero').hidden = false;
        actualizar();
    } catch (error) {
        escribir('estado', 'No se pudieron cargar los datos de dw/. Revisá que la carpeta exista y que la página se abra desde un servidor.');
        console.error(error);
    }
}

iniciar();