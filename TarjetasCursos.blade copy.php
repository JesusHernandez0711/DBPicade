@props(['curso'])

@php
    /** * █ LÓGICA DE NEGOCIO FORENSIC: INTEGRIDAD DINÁMICA 
     * Mapeamos los campos del SP a la lógica visual del componente.
     */
    
    // 1. Fechas y Límites
    $fechaInicio = \Carbon\Carbon::parse($curso->Fecha_Inicio);
    $fechaLimite = $fechaInicio->copy()->subWeek(); // Cierre 7 días antes
    $hoy = now();

    // 2. Variables de Control (Basadas en nombres reales del SP)
    $inscritos = $curso->Inscritos ?? 0;
    $cupoMax = $curso->Cupo ?? 30;
    
    // 3. Determinación de Estado Atómico
    $cupoLleno = $inscritos >= $cupoMax;
    $registroVencido = $hoy->greaterThan($fechaLimite);
    $estaAbierto = !$cupoLleno && !$registroVencido;
    
    // 4. Configuración Estética Semántica
    $estadoColor = $estaAbierto ? 'success' : 'danger';
    $estadoTexto = $estaAbierto ? 'ABIERTO' : 'CERRADO';
    
    if ($cupoLleno) $estadoTexto = 'CUPO LLENO';
    if ($registroVencido && $estaAbierto) $estadoTexto = 'PRÓXIMO A INICIAR';
    if ($hoy->greaterThan($fechaInicio)) $estadoTexto = 'EN CURSO / FINALIZADO';
@endphp

<div class="col-12 col-md-6 col-xl-4 mb-4">
    <div class="card h-100 border-0 shadow-sm overflow-hidden hover-scale rounded-4">
        
        {{-- ENCABEZADO: Identificación y Estatus --}}
        <div class="card-header border-0 d-flex justify-content-between align-items-center py-3 bg-light" 
             style="border-bottom: 4px solid {{ $estaAbierto ? '#28a745' : '#6c757d' }} !important;">
            
            <h6 class="m-0 fw-bold text-muted">#{{ $curso->Folio_Curso ?? 'S/F' }}</h6>
            
            <span class="badge rounded-pill bg-{{ $estadoColor }} px-3 py-2 shadow-sm">
                {{ $estadoTexto }}
            </span>
        </div>

        <div class="card-body p-4">
            {{-- TÍTULO Y ADSCRIPCIÓN --}}
            <h5 class="fw-bold mb-2 text-dark">{{ $curso->Nombre_Tema }}</h5>
            <div class="d-flex align-items-center text-muted small mb-3">
                <i class="bi bi-building me-2 text-guinda"></i>
                <span class="text-uppercase fw-bold">{{ $curso->Nombre_Gerencia ?? 'Gerencia No Definida' }}</span>
            </div>

            {{-- MATRIZ DE DATOS CLAVE --}}
            <div class="bg-light rounded-3 p-3 mb-3 border border-light">
                <div class="row g-2 small">
                    <div class="col-6">
                        <span class="text-muted d-block x-small text-uppercase fw-bold">Modalidad</span>
                        <span class="fw-bold">{{ $curso->Nombre_Sede ?? 'Virtual' }}</span>
                    </div>
                    <div class="col-6 text-end border-start">
                        <span class="text-muted d-block x-small text-uppercase fw-bold">Límite Registro</span>
                        <span class="text-primary fw-bold">{{ $fechaLimite->format('d/M/Y') }}</span>
                    </div>
                </div>
            </div>

            {{-- DETALLE DE INSTRUCTOR --}}
            <div class="d-flex align-items-center mb-4">
                <div class="bg-guinda-light rounded-circle p-2 me-3">
                    <i class="bi bi-person-video3 text-guinda"></i>
                </div>
                <div>
                    <p class="x-small text-muted mb-0 fw-bold text-uppercase">Instructor Asignado</p>
                    <p class="small mb-0 fw-bold">{{ $curso->Instructor ?? 'Personal por asignar' }}</p>
                </div>
            </div>

            {{-- INDICADORES DE CUPO (VISTA FORENSIC) --}}
            <div class="mb-4">
                <div class="d-flex justify-content-between small mb-1">
                    <span class="fw-bold">Ocupación del Grupo</span>
                    <span class="fw-bold">{{ $inscritos }} / {{ $cupoMax }}</span>
                </div>
                <div class="progress" style="height: 6px;">
                    @php $porcentaje = ($inscritos / $cupoMax) * 100; @endphp
                    <div class="progress-bar bg-{{ $porcentaje > 80 ? 'warning' : 'success' }}" 
                         role="progressbar" style="width: {{ $porcentaje }}%"></div>
                </div>
            </div>

            {{-- ACCIÓN DINÁMICA --}}
            <div class="d-grid">
                @if($estaAbierto)
                    <a href="{{ route('cursos.inscripcion', $curso->Id_Capacitacion ?? 0) }}" 
                       class="btn btn-guinda btn-lg rounded-pill fw-bold shadow-sm">
                        <i class="bi bi-send-check me-2"></i>SOLICITAR INSCRIPCIÓN
                    </a>
                @else
                    <button class="btn btn-secondary btn-lg rounded-pill fw-bold" disabled>
                        <i class="bi bi-lock-fill me-2"></i>REGISTRO NO DISPONIBLE
                    </button>
                @endif
            </div>
        </div>
    </div>
</div>
