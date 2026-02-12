@extends('layouts.Panel')

@section('title', 'Admin Dashboard')
@section('header', 'Tablero de Control')

@section('content')
<div class="container-fluid">
    
    <div class="row g-4 mb-4">
        
        <div class="col-sm-6 col-xl-3">
            <div class="card text-white bg-primary h-100 shadow-sm border-0 position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #6f42c1, #8e44ad);"> {{-- Gradiente Morado --}}
                <div class="card-body pb-0 d-flex justify-content-between align-items-start">
                    <div>
                        <div class="fs-4 fw-semibold">
                            {{ $stats['total_usuarios'] }} <span class="fs-6 fw-normal text-white-50">({{ $stats['nuevos_hoy'] }} nuevos)</span>
                        </div>
                        <div>Usuarios Globales</div>
                    </div>
                    <div class="dropdown">
                        <button class="btn btn-transparent text-white p-0" type="button">
                            <i class="bi bi-three-dots-vertical"></i>
                        </button>
                    </div>
                </div>
                <div class="chart-wrapper mt-3 mx-3" style="height:70px;">
                    <i class="bi bi-people-fill position-absolute bottom-0 end-0 opacity-25" style="font-size: 5rem; transform: rotate(-15deg); margin-right: -10px;"></i>
                </div>
                <a href="{{ route('usuarios.index') }}" class="stretched-link"></a>
            </div>
        </div>

        <div class="col-sm-6 col-xl-3">
            <div class="card text-white bg-info h-100 shadow-sm border-0 position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #0d6efd, #3498db);"> {{-- Gradiente Azul --}}
                <div class="card-body pb-0 d-flex justify-content-between align-items-start">
                    <div>
                        <div class="fs-4 fw-semibold">{{ date('Y') }}</div>
                        <div>Matriz Operativa</div>
                        <p class="small opacity-75 mb-3">Programación anual, estatus de cursos y reportes operativos.</p>
                    </div>
                    <div class="dropdown">
                        <button class="btn btn-transparent text-white p-0" type="button">
                            <i class="bi bi-three-dots-vertical"></i>
                        </button>
                    </div>
                </div>
                <div class="chart-wrapper mt-3 mx-3" style="height:70px;">
                    <i class="bi bi-easel-fill position-absolute bottom-0 end-0 opacity-25" style="font-size: 5rem; transform: rotate(-15deg); margin-right: -10px;"></i>
                </div>
                <a href="#" class="stretched-link"></a>
            </div>
        </div>

        <div class="col-sm-6 col-xl-3">
            <div class="card text-white bg-warning h-100 shadow-sm border-0 position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #ffc107, #f1c40f);"> {{-- Gradiente Amarillo --}}
                <div class="card-body pb-0 d-flex justify-content-between align-items-start">
                    <div>
                        <div class="fs-4 fw-semibold">Alumno</div>
                        <div>Mi Kárdex</div>
                        <p class="small opacity-75 mb-3">Consulta tu historial personal y descargas de DC-3.</p>

                    </div>
                    <div class="dropdown">
                        <button class="btn btn-transparent text-white p-0" type="button">
                            <i class="bi bi-three-dots-vertical"></i>
                        </button>
                    </div>
                </div>
                <div class="chart-wrapper mt-3 mx-3" style="height:70px;">
                    <i class="bi bi-mortarboard-fill position-absolute bottom-0 end-0 opacity-25" style="font-size: 5rem; transform: rotate(-15deg); margin-right: -10px;"></i>
                </div>
                <a href="#" class="stretched-link"></a>
            </div>
        </div>

        <div class="col-sm-6 col-xl-3">
            <div class="card text-white bg-danger h-100 shadow-sm border-0 position-relative overflow-hidden" 
                 style="background: linear-gradient(135deg, #dc3545, #e74c3c);"> {{-- Gradiente Rojo --}}
                <div class="card-body pb-0 d-flex justify-content-between align-items-start">
                    <div>
                        <div class="fs-4 fw-semibold">Docencia</div>
                        <div>Panel Instructor</div>
                        <p class="small opacity-75 mb-3">Listas de asistencia y captura de calificaciones.</p>
                    </div>
                    <div class="dropdown">
                        <button class="btn btn-transparent text-white p-0" type="button">
                            <i class="bi bi-three-dots-vertical"></i>
                        </button>
                    </div>
                </div>
                <div class="chart-wrapper mt-3 mx-3" style="height:70px;">
                    <i class="bi bi-person-video3 position-absolute bottom-0 end-0 opacity-25" style="font-size: 5rem; transform: rotate(-15deg); margin-right: -10px;"></i>
                </div>
                <a href="#" class="stretched-link"></a>
            </div>
        </div>
    </div>

    <div class="row g-4 mb-4">
        <div class="col-md-12">
            <div class="card shadow-sm border-0">
                <div class="card-header bg-white py-3 d-flex justify-content-between align-items-center">
                    <h5 class="mb-0 fw-bold text-secondary">
                        <i class="bi bi-bar-chart-line-fill me-2 text-primary"></i>
                        Métricas de Capacitación
                    </h5>
                    <button class="btn btn-outline-dark btn-sm" type="button" data-bs-toggle="offcanvas" data-bs-target="#offcanvasCatalogs">
                        <i class="bi bi-gear-fill me-1"></i> Configurar Catálogos
                    </button>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-lg-6 mb-4 mb-lg-0 border-end">
                            <h6 class="text-center text-muted mb-3">Eficiencia por Gerencia</h6>
                            <div style="height: 300px;">
                                <canvas id="chartEficiencia"></canvas>
                            </div>
                        </div>
                        <div class="col-lg-6">
                            <h6 class="text-center text-muted mb-3">Top 10 Temas Más Solicitados</h6>
                            <div style="height: 300px;">
                                <canvas id="chartTopTemas"></canvas>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="card-footer bg-light">
                    <div class="row text-center">
                        <div class="col-sm-6 col-md-3">
                            <div class="text-muted small">CPU Usage</div>
                            <div class="fw-bold">{{ number_format($cpuLoad, 1) }}%</div>
                            <div class="progress progress-thin mt-1" style="height: 4px;">
                                <div class="progress-bar bg-success" role="progressbar" style="width: {{ $cpuLoad }}%"></div>
                            </div>
                        </div>
                        <div class="col-sm-6 col-md-3">
                            <div class="text-muted small">Memory</div>
                            <div class="fw-bold">{{ $memoryUsage }} MB</div>
                            <div class="progress progress-thin mt-1" style="height: 4px;">
                                <div class="progress-bar bg-warning" role="progressbar" style="width: 40%"></div>
                            </div>
                        </div>
                        <div class="col-sm-6 col-md-3">
                            <div class="text-muted small">Users Active</div>
                            <div class="fw-bold">{{ $stats['usuarios_activos'] }}</div>
                            <div class="progress progress-thin mt-1" style="height: 4px;">
                                <div class="progress-bar bg-danger" role="progressbar" style="width: 60%"></div>
                            </div>
                        </div>
                        <div class="col-sm-6 col-md-3">
                            <div class="text-muted small">DB Status</div>
                            <div class="fw-bold text-success">Connected</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

</div>
@endsection

@push('scripts')
<script>
    /*
     * --------------------------------------------------------------------------
     * INICIALIZACIÓN DE GRÁFICAS (Chart.js)
     * Datos inyectados desde Laravel Controller usando json_encode seguro.
     * --------------------------------------------------------------------------
     */

    // 1. GRÁFICA DE BARRAS VERTICALES (Gerencias)
    const ctxEficiencia = document.getElementById('chartEficiencia');
    if (ctxEficiencia) {
        new Chart(ctxEficiencia, {
            type: 'bar',
            data: {
                labels: {!! json_encode($graficaGerencias['labels']) !!},
                datasets: [{
                    label: 'Cursos Completados',
                    backgroundColor: 'rgba(50, 31, 219, 0.8)', // Azul CoreUI
                    borderColor: 'rgba(50, 31, 219, 1)',
                    borderWidth: 1,
                    data: {!! json_encode($graficaGerencias['data']) !!},
                    barPercentage: 0.5
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    y: { beginAtZero: true, grid: { borderDash: [2, 2] } },
                    x: { grid: { display: false } }
                }
            }
        });
    }

    // 2. GRÁFICA DE BARRAS HORIZONTALES (Top Temas)
    const ctxTopTemas = document.getElementById('chartTopTemas');
    if (ctxTopTemas) {
        new Chart(ctxTopTemas, {
            type: 'bar',
            indexAxis: 'y', // ESTO LA HACE HORIZONTAL
            data: {
                labels: {!! json_encode($topCursosLabels) !!},
                datasets: [{
                    label: 'Veces Impartido',
                    backgroundColor: '#f9b115', // Amarillo CoreUI
                    data: {!! json_encode($topCursosValues) !!},
                    borderRadius: 4,
                    barPercentage: 0.6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    x: { beginAtZero: true, grid: { borderDash: [2, 2] } },
                    y: { grid: { display: false } }
                }
            }
        });
    }
</script>
@endpush