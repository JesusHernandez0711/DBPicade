{{-- 
    VISTA: Dashboard de Administrador
    UBICACIÓN: resources/views/panel/admin/dashboard.blade.php
    CONTROLADOR: DashboardController::adminDashboard()
    
    DESCRIPCIÓN:
    Tablero de mando principal. Muestra KPIs globales, acceso a módulos críticos 
    y visualización de datos de inteligencia de negocios (BI).
--}}

@extends('layouts.Panel') {{-- Hereda la estructura base (Sidebar + Navbar) --}}

@section('title', 'Admin Dashboard')
@section('header', 'Tablero de Mando Administrativo')

@section('content')
<div class="container-fluid">
    
    <div class="row g-4 mb-4">
        
        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-white position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #6f42c1, #8e44ad);"> {{-- Gradiente Morado --}}
                
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Usuarios Globales</h6>
                            <h2 class="mb-0 fw-bold">{{ $stats['total_usuarios'] }}</h2> {{-- Dato inyectado desde Controller --}}
                        </div>
                        <i class="bi bi-people-fill fs-1 opacity-25 position-absolute end-0 top-0 m-3"></i>
                    </div>
                    
                    <div class="small mb-3">
                        <span class="badge bg-white text-dark bg-opacity-25">+{{ $stats['nuevos_hoy'] }} hoy</span>
                        <span class="ms-2 opacity-75">{{ $stats['usuarios_activos'] }} activos</span>
                    </div>

                    <a href="{{ route('usuarios.index') }}" class="btn btn-sm btn-light text-primary w-100 fw-bold stretched-link">
                        Administrar Usuarios <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>

        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-white position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #0d6efd, #3498db);"> {{-- Gradiente Azul --}}
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Matriz {{ date('Y') }}</h6>
                            <h2 class="mb-0 fw-bold">Gestión</h2> 
                        </div>
                        <i class="bi bi-easel-fill fs-1 opacity-25 position-absolute end-0 top-0 m-3"></i>
                    </div>
                    <p class="small opacity-75 mb-3">Programación anual, estatus de cursos y reportes operativos.</p>
                    
                    <a href="#" class="btn btn-sm btn-light text-primary w-100 fw-bold stretched-link">
                        Ir a Matriz <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>

        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-dark position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #ffc107, #f1c40f);"> {{-- Gradiente Amarillo --}}
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Mi Kárdex</h6>
                            <h5 class="mb-0 fw-bold">Alumno</h5>
                        </div>
                        <i class="bi bi-mortarboard-fill fs-1 opacity-25 position-absolute end-0 top-0 m-3"></i>
                    </div>
                    <p class="small opacity-75 mb-3">Consulta tu historial personal y descargas de DC-3.</p>
                    <a href="#" class="btn btn-sm btn-dark text-warning w-100 fw-bold stretched-link">
                        Ver Mis Cursos <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>

        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-white position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #dc3545, #e74c3c);"> {{-- Gradiente Rojo --}}
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Docencia</h6>
                            <h5 class="mb-0 fw-bold">Instructor</h5>
                        </div>
                        <i class="bi bi-person-video3 fs-1 opacity-25 position-absolute end-0 top-0 m-3"></i>
                    </div>
                    <p class="small opacity-75 mb-3">Listas de asistencia y captura de calificaciones.</p>
                    <a href="#" class="btn btn-sm btn-light text-danger w-100 fw-bold stretched-link">
                        Panel Instructor <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>
    </div>

    <div class="row mb-4">
        
        <div class="col-md-9">
            <div class="card border-0 shadow-sm h-100">
                <div class="card-body p-4 d-flex flex-column justify-content-center">
                    <h5 class="fw-bold mb-3"><i class="bi bi-search me-2 text-primary"></i>Buscador Global</h5>
                    <form action="#" method="GET">
                        <div class="input-group input-group-lg">
                            <input type="text" class="form-control bg-light border" placeholder="Buscar folio, tema o instructor en todo el histórico..." name="q">
                            <button class="btn btn-primary px-4" type="submit">BUSCAR</button>
                        </div>
                        <div class="form-text text-muted mt-2">
                            <i class="bi bi-info-circle"></i> Rastrea expedientes incluso en cursos archivados de años anteriores.
                        </div>
                    </form>
                </div>
            </div>
        </div>

        <div class="col-md-3">
            <div class="card border-0 shadow-sm h-100 bg-dark text-white cursor-pointer hover-scale" 
                 type="button" 
                 data-bs-toggle="offcanvas" 
                 data-bs-target="#offcanvasCatalogs" 
                 aria-controls="offcanvasCatalogs"> {{-- Conecta con el ID definido en layouts.panel --}}
                
                <div class="card-body d-flex align-items-center justify-content-center flex-column text-center">
                    <div class="rounded-circle bg-warning bg-opacity-25 p-3 mb-3">
                        <i class="bi bi-database-gear fs-2 text-warning"></i>
                    </div>
                    <h6 class="mb-1 fw-bold">Administrar Catálogos</h6>
                    <small class="text-muted">Gerencias, Puestos, Sedes...</small>
                </div>
            </div>
        </div>
    </div>

    <div class="row g-4 mb-4">
        
        <div class="col-lg-6">
            <div class="card border-0 shadow-sm h-100">
                <div class="card-header bg-white d-flex justify-content-between align-items-center py-3 border-0">
                    <h6 class="fw-bold mb-0 text-secondary">
                        <i class="bi bi-bar-chart-fill me-2 text-guinda"></i>Eficiencia Operativa
                    </h6>
                    <span class="badge bg-light text-dark border">Top 5 Gerencias</span>
                </div>
                <div class="card-body">
                    <canvas id="chartEficiencia" style="max-height: 250px;"></canvas>
                </div>
            </div>
        </div>

        <div class="col-lg-6">
            <div class="card border-0 shadow-sm h-100">
                <div class="card-header bg-white d-flex justify-content-between align-items-center py-3 border-0">
                    <h6 class="fw-bold mb-0 text-secondary">
                        <i class="bi bi-trophy-fill me-2 text-warning"></i>Cursos Más Solicitados
                    </h6>
                    <span class="badge bg-light text-dark border">Top 10 Histórico</span>
                </div>
                <div class="card-body">
                    <canvas id="chartTopTemas" style="max-height: 250px;"></canvas>
                </div>
            </div>
        </div>
    </div>

    <div class="card border-0 shadow-sm bg-light mb-4">
        <div class="card-body d-flex justify-content-around align-items-center flex-wrap gap-4 py-4">
            
            <div class="text-center">
                <h6 class="text-muted mb-1 small text-uppercase">Uso de CPU</h6>
                <div class="d-flex align-items-center justify-content-center gap-2">
                    <i class="bi bi-cpu text-secondary"></i>
                    <h4 class="fw-bold text-dark mb-0">{{ number_format($cpuLoad, 1) }}%</h4>
                </div>
            </div>
            
            <div class="vr d-none d-md-block opacity-25"></div>
            
            <div class="text-center">
                <h6 class="text-muted mb-1 small text-uppercase">Memoria PHP</h6>
                <div class="d-flex align-items-center justify-content-center gap-2">
                    <i class="bi bi-memory text-secondary"></i>
                    <h4 class="fw-bold text-info mb-0">{{ $memoryUsage }} MB</h4>
                </div>
            </div>
            
            <div class="vr d-none d-md-block opacity-25"></div>
            
            <div class="text-center">
                <h6 class="text-muted mb-1 small text-uppercase">Estado BD</h6>
                <div class="d-flex align-items-center justify-content-center gap-2">
                    <i class="bi bi-database-check text-success"></i>
                    <h4 class="fw-bold text-success mb-0">Conectado</h4>
                </div>
            </div>

        </div>
    </div>

</div>
@endsection

{{-- 
    SECCIÓN DE SCRIPTS
    Aquí se inicializan las librerías JS específicas de esta vista.
--}}@push('scripts')
<script>
    /**
     * CONFIGURACIÓN DE GRÁFICAS (Chart.js)
     * Se utilizan los datos pasados desde Laravel mediante la directiva json (sin arroba para no romper blade)
     */

    // -------------------------------------------------------
    // GRÁFICA 1: EFICIENCIA (Barras Verticales)
    // -------------------------------------------------------
    const ctxEficiencia = document.getElementById('chartEficiencia');
    if(ctxEficiencia) {
        // Datos seguros desde PHP
        const labelsGerencia = {!! json_encode($graficaGerencias['labels']) !!};
        const dataGerencia   = {!! json_encode($graficaGerencias['data']) !!};

        new Chart(ctxEficiencia, {
            type: 'bar',
            data: {
                labels: labelsGerencia, 
                datasets: [{
                    label: 'Cursos Completados',
                    data: dataGerencia, 
                    backgroundColor: '#731834', // Guinda Institucional
                    borderRadius: 4,
                    barPercentage: 0.6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { 
                    y: { beginAtZero: true, grid: { borderDash: [2, 4] } },
                    x: { grid: { display: false } }
                }
            }
        });
    }

    // -------------------------------------------------------
    // GRÁFICA 2: TOP 10 TEMAS (Barras Horizontales)
    // -------------------------------------------------------
    const ctxTopTemas = document.getElementById('chartTopTemas');
    if(ctxTopTemas) {
        // Datos seguros desde PHP
        const labelsTemas = {!! json_encode($topCursosLabels) !!};
        const valuesTemas = {!! json_encode($topCursosValues) !!};

        new Chart(ctxTopTemas, {
            type: 'bar',
            indexAxis: 'y', // <--- IMPORTANTE: Esto rota la gráfica a horizontal
            data: {
                labels: labelsTemas, 
                datasets: [{
                    label: 'Veces Impartido',
                    data: valuesTemas, 
                    backgroundColor: '#bfa15f',    // Color Dorado Institucional
                    borderRadius: 4,
                    barPercentage: 0.7
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { 
                    x: { beginAtZero: true, grid: { borderDash: [2, 4] } },
                    y: { grid: { display: false } }
                }
            }
        });
    }
</script>

<style>
    /* Efecto Hover para las tarjetas interactivas */
    .hover-scale { transition: transform 0.2s ease; }
    .hover-scale:hover { transform: scale(1.02); cursor: pointer; }
</style>
@endpush