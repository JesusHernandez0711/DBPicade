{{-- 
    UBICACIÓN: resources/views/components/Impartidos.blade.php
    ESTÁNDAR:  Platinum Forensic V.5
    LÓGICA:    Componente Autónomo de Gestión Docente
--}}
@extends('layouts.Panel')

@section('title', 'Gestión de Instrucción')

@section('content')
<div class="container-fluid py-4">
    
    {{-- █ 1. ENCABEZADO DE ALTO NIVEL (MATCH CON KÁRDEX) █ --}}
    <div class="d-flex flex-column flex-md-row justify-content-between align-items-center mb-4 fade-in-up">
        <div class="mb-3 mb-md-0">
            <h2 class="fw-bold text-dark mb-0">Módulo de Instrucción</h2>
            <div class="d-flex align-items-center gap-2 mt-2">
                {{-- KPI: Total de Cursos --}}
                <span class="badge bg-white text-secondary border shadow-sm rounded-pill fw-normal px-3">
                    <i class="bi bi-collection me-1"></i>Total: {{ $cursos->count() }}
                </span>
                {{-- KPI: Acción Requerida (ID 8 = En Evaluación) --}}
                @php $pendientes = $cursos->where('Id_Estatus_Snapshot', 8)->count(); @endphp
                @if($pendientes > 0)
                    <span class="badge bg-warning text-dark border border-warning rounded-pill fw-bold px-3 animate-pulse">
                        <i class="bi bi-exclamation-circle-fill me-1"></i>Por Evaluar: {{ $pendientes }}
                    </span>
                @else
                    <span class="badge bg-success bg-opacity-10 text-success border border-success border-opacity-25 rounded-pill fw-normal px-3">
                        <i class="bi bi-check-circle me-1"></i>Al día
                    </span>
                @endif
            </div>
        </div>
        
        {{-- Botón de Retorno "Guinda Institucional" --}}
        <a href="{{ route('dashboard') }}" class="btn btn-danger rounded-pill px-4 shadow-sm fw-bold hover-scale" 
           style="background-color: #731834; border-color: #731834;">
            <i class="bi bi-arrow-left me-2"></i>Volver al Dashboard
        </a>
    </div>

    {{-- █ 2. BUSCADOR FLOTANTE CENTRALIZADO █ --}}
    <div class="row justify-content-center mb-4 fade-in-up" style="animation-delay: 0.1s;">
        <div class="col-lg-6 col-md-8">
            <div class="input-group input-group-lg shadow-sm rounded-pill overflow-hidden bg-white border">
                <span class="input-group-text bg-white border-0 ps-4 text-muted">
                    <i class="bi bi-search"></i>
                </span>
                {{-- ID para el script de filtrado local --}}
                <input type="text" id="filterImpartidos" class="form-control border-0" 
                       placeholder="Buscar por folio, tema, periodo o estatus..." 
                       autocomplete="off">
            </div>
        </div>
    </div>

    {{-- █ 3. TARJETA DE DATOS (TABLA FORENSE) █ --}}
    <div class="card border-0 shadow-sm rounded-4 overflow-hidden fade-in-up" style="animation-delay: 0.2s;">
        <div class="table-responsive">
            <table class="table table-hover align-middle mb-0" id="tablaImpartidos">
                <thead class="bg-light text-secondary small text-uppercase fw-bold">
                    <tr>
                        <th class="ps-4 py-3" style="min-width: 250px;">Capacitación / Folio</th>
                        <th style="min-width: 150px;">Impacto / Cupo</th>
                        <th style="min-width: 150px;">Periodo</th>
                        <th class="text-center">Estatus</th>
                        <th class="text-end pe-4">Acciones</th>
                    </tr>
                </thead>
                <tbody class="bg-white">
                    @forelse($cursos as $curso)
                    <tr class="item-impartido border-bottom-hover">
                        
                        {{-- A. Identidad del Curso --}}
                        <td class="ps-4 py-3">
                            <div class="d-flex flex-column">
                                <span class="fw-bold text-dark mb-1 text-wrap text-uppercase" style="font-size: 0.95rem;">
                                    {{ $curso->Tema_Curso }}
                                </span>
                                <span class="badge bg-light text-muted border w-auto align-self-start font-monospace shadow-sm">
                                    <i class="bi bi-upc-scan me-1"></i>{{ $curso->Folio_Curso }}
                                </span>
                            </div>
                        </td>

                        {{-- B. Barra de Progreso (Impacto) --}}
                        <td>
                            <div class="d-flex flex-column gap-1">
                                <div class="d-flex justify-content-between small">
                                    <span class="fw-bold">{{ $curso->Asistentes_Confirmados }} Inscritos</span>
                                    <span class="text-muted">Meta: {{ $curso->Cupo_Programado }}</span>
                                </div>
                                <div class="progress" style="height: 6px; border-radius: 4px; background-color: #e9ecef;">
                                    @php 
                                        $porc = ($curso->Cupo_Programado > 0) ? ($curso->Asistentes_Confirmados * 100 / $curso->Cupo_Programado) : 0;
                                        $barColor = $porc < 30 ? 'bg-danger' : ($porc < 80 ? 'bg-primary' : 'bg-success');
                                    @endphp
                                    <div class="progress-bar {{ $barColor }}" style="width: {{ $porc }}%"></div>
                                </div>
                            </div>
                        </td>

                        {{-- C. Fechas --}}
                        <td>
                            <div class="small text-muted">
                                <div class="mb-1">
                                    <i class="bi bi-calendar-event me-2 text-primary"></i>{{ \Carbon\Carbon::parse($curso->Fecha_Inicio)->format('d M, Y') }}
                                </div>
                                <div>
                                    <i class="bi bi-flag me-2 text-secondary"></i>{{ \Carbon\Carbon::parse($curso->Fecha_Fin)->format('d M, Y') }}
                                </div>
                            </div>
                        </td>

                        {{-- D. Semáforo de Estatus (LÓGICA DE IDs REALES) --}}
                        <td class="text-center">
                            @php
                                // Mapeo estricto basado en Vista_Estatus_Capacitacion
                                $statusConfig = match((int)$curso->Id_Estatus_Snapshot) {
                                    1, 7   => ['color' => 'info',    'icon' => 'bi-hourglass-split', 'label' => 'Programado'],
                                    2      => ['color' => 'primary', 'icon' => 'bi-play-circle-fill', 'label' => 'En Curso'],
                                    3, 9   => ['color' => 'success', 'icon' => 'bi-check-circle-fill', 'label' => 'Finalizado'],
                                    4      => ['color' => 'danger',  'icon' => 'bi-x-circle-fill',     'label' => 'Cancelado'],
                                    8      => ['color' => 'warning', 'icon' => 'bi-pencil-square',     'label' => 'En Evaluación'], // ID CLAVE
                                    10     => ['color' => 'dark',    'icon' => 'bi-archive-fill',      'label' => 'Cerrado'],
                                    default => ['color' => 'secondary','icon' => 'bi-question-circle', 'label' => $curso->Estatus_Snapshot]
                                };
                            @endphp
                            <span class="badge bg-{{ $statusConfig['color'] }} bg-opacity-10 text-{{ $statusConfig['color'] }} border border-{{ $statusConfig['color'] }} border-opacity-25 rounded-pill px-3 py-2">
                                <i class="bi {{ $statusConfig['icon'] }} me-1"></i>{{ $statusConfig['label'] }}
                            </span>
                        </td>

                        {{-- E. Botonera de Acciones --}}
                        <td class="text-end pe-4">
                            <div class="btn-group shadow-sm" role="group">
                                {{-- 1. VER LISTA (Llama al script blindado en Picade.js) --}}
                                <button type="button" 
                                        class="btn btn-outline-secondary btn-sm"
                                        onclick="loadParticipants({{ $curso->Id_Detalle_de_Capacitacion }}, '{{ $curso->Folio_Curso }}')"
                                        data-bs-toggle="tooltip" 
                                        title="Ver Lista de Participantes">
                                    <i class="bi bi-people-fill"></i>
                                </button>

                                {{-- 2. EVALUAR (Solo desbloqueado si ID == 8) --}}
                                @if((int)$curso->Id_Estatus_Snapshot === 8)
                                    {{-- Aquí pondremos la ruta real de evaluación cuando la creemos --}}
                                    <a href="#" 
                                       class="btn btn-warning btn-sm fw-bold text-dark border-start"
                                       title="Evaluación Pendiente">
                                        <i class="bi bi-pencil-square me-1"></i>EVALUAR
                                    </a>
                                @else
                                    <button class="btn btn-light btn-sm text-muted border-start" disabled 
                                            style="background-color: #f8f9fa;" title="Acción no disponible en este estatus">
                                        <i class="bi bi-lock-fill opacity-50"></i>
                                    </button>
                                @endif
                            </div>
                        </td>
                    </tr>
                    @empty
                    {{-- Estado Vacío (Empty State) Platinum --}}
                    <tr>
                        <td colspan="5" class="text-center py-5">
                            <div class="d-flex flex-column align-items-center justify-content-center opacity-50">
                                <i class="bi bi-folder2-open display-1 text-secondary mb-3"></i>
                                <h5 class="text-muted fw-bold">Sin asignaciones activas</h5>
                                <p class="small text-secondary mb-0">No se encontraron cursos vinculados a tu perfil de instructor.</p>
                            </div>
                        </td>
                    </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>

{{-- █ MODAL LISTA DE PARTICIPANTES (Contenedor para AJAX) █ --}}
<div class="modal fade" id="modalParticipantes" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-lg modal-dialog-centered modal-dialog-scrollable">
        <div class="modal-content border-0 shadow-lg rounded-4">
            <div class="modal-header bg-primary text-white border-0">
                <div class="d-flex align-items-center">
                    <div class="bg-white bg-opacity-25 rounded-circle p-2 me-3">
                        <i class="bi bi-people-fill fs-4 text-white"></i>
                    </div>
                    <div>
                        <h5 class="modal-title fw-bold mb-0">Nómina de Participantes</h5>
                        <small class="opacity-75 font-monospace" id="modalSubtitle">Cargando referencia...</small>
                    </div>
                </div>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            
            {{-- Cuerpo vacío: Picade.js inyectará aquí el HTML seguro --}}
            <div class="modal-body p-0" id="modalBodyParticipants"></div>
        </div>
    </div>
</div>

@endsection