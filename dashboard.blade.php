@extends('layouts.Panel')

@section('title', 'Admin Dashboard')
@section('header', 'Tablero de Control')

@section('content')
<div class="container-fluid">
    
<div class="row g-4 mb-4">
        
        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-white" 
                 style="background-color: #6f42c1;"> {{-- Color Sólido Morado --}}
                
                <div class="card-body p-4">
                    <div class="d-flex justify-content-between align-items-start position-relative z-1">
                        <div>
                            <div class="text-uppercase fw-bold opacity-75 small mb-1">USUARIOS GLOBALES</div>
                            <h2 class="fw-bold mb-2">{{ $stats['total_usuarios'] }}</h2>
                            <div class="small">
                                <span class="badge bg-black bg-opacity-25 me-1">+{{ $stats['nuevos_hoy'] }} hoy</span>
                                <span class="opacity-75">{{ $stats['usuarios_activos'] }} activos</span>
                            </div>
                        </div>
                        <div class="dropdown">
                            <i class="bi bi-three-dots-vertical opacity-75"></i>
                        </div>
                    </div>
                    <i class="bi bi-people-fill position-absolute" 
                       style="font-size: 8rem; bottom: -20px; right: -20px; opacity: 0.15; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="{{ route('usuarios.index') }}" class="stretched-link"></a>
            </div>
        </div>

        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-white" 
                 style="background-color: #0d6efd;"> {{-- Color Sólido Azul --}}
                
                <div class="card-body p-4">
                    <div class="d-flex justify-content-between align-items-start position-relative z-1">
                        <div>
                            <div class="text-uppercase fw-bold opacity-75 small mb-1">PICADE {{ date('Y') }}</div>
                            <h3 class="fw-bold mb-2">Gestión</h3>
                            <p class="small opacity-75 mb-0 lh-sm">
                                Programación anual, estatus de cursos y reportes.
                            </p>
                        </div>
                        <div class="dropdown">
                            <i class="bi bi-three-dots-vertical opacity-75"></i>
                        </div>
                    </div>
                    <i class="bi bi-easel-fill position-absolute" 
                       style="font-size: 8rem; bottom: -20px; right: -20px; opacity: 0.15; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="#" class="stretched-link"></a>
            </div>
        </div>

        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-dark" 
                 style="background-color: #ffc107;"> {{-- Color Sólido Amarillo --}}
                
                <div class="card-body p-4">
                    <div class="d-flex justify-content-between align-items-start position-relative z-1">
                        <div>
                            <div class="text-uppercase fw-bold opacity-50 small mb-1">MI KÁRDEX</div>
                            <h3 class="fw-bold mb-2">Alumno</h3>
                            <p class="small opacity-75 mb-0 lh-sm">
                                Consulta tu historial personal y descargas de DC-3.
                            </p>
                        </div>
                        <div class="dropdown">
                            <i class="bi bi-three-dots-vertical opacity-50"></i>
                        </div>
                    </div>
                    <i class="bi bi-mortarboard-fill position-absolute" 
                       style="font-size: 8rem; bottom: -20px; right: -20px; opacity: 0.15; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="#" class="stretched-link"></a>
            </div>
        </div>

        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-white" 
                 style="background-color: #dc3545;"> {{-- Color Sólido Rojo --}}
                
                <div class="card-body p-4">
                    <div class="d-flex justify-content-between align-items-start position-relative z-1">
                        <div>
                            <div class="text-uppercase fw-bold opacity-75 small mb-1">DOCENCIA</div>
                            <h3 class="fw-bold mb-2">Instructor</h3> <p class="small opacity-75 mb-0 lh-sm">
                                Listas de asistencia y captura de calificaciones.
                            </p>
                        </div>
                        <div class="dropdown">
                            <i class="bi bi-three-dots-vertical opacity-75"></i>
                        </div>
                    </div>
                    
                    <i class="bi bi-person-video3 position-absolute" 
                       style="font-size: 8rem; bottom: -20px; right: -20px; opacity: 0.15; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="#" class="stretched-link"></a>
            </div>
        </div>
    </div>

    <div class="row mb-4">
        <div class="col-12"> <div class="card border-0 shadow-sm">
                <div class="card-body p-4">
                    
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <h5 class="fw-bold mb-0 text-secondary">
                            <i class="bi bi-search me-2 text-primary"></i>Buscador Global
                        </h5>
                        
                        <button class="btn btn-outline-dark btn-sm fw-bold" type="button" data-bs-toggle="offcanvas" data-bs-target="#offcanvasCatalogs">
                            <i class="bi bi-gear-fill me-1"></i> Configurar Catálogos
                        </button>
                    </div>

                    <form action="#" method="GET">
                        <div class="input-group input-group-lg">
                            <input type="text" class="form-control bg-light border" placeholder="Buscar folio, tema o instructor en todo el histórico..." name="q">
                            <button class="btn btn-primary px-5 fw-bold" type="submit">BUSCAR</button>
                        </div>
                        <div class="form-text text-muted mt-2">
                            <i class="bi bi-info-circle me-1"></i> Rastrea expedientes incluso en cursos archivados de años anteriores.
                        </div>
                    </form>

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