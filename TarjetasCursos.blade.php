@props(['curso'])

@php
    // Lógica de Negocio Forensic: Determinación de Estado
    // 1. Calculamos fecha límite (ej. 1 semana antes del inicio)
    $fechaInicio = \Carbon\Carbon::parse($curso->fecha_inicio);
    $fechaLimite = $fechaInicio->copy()->subWeek();
    $hoy = now();

    // 2. Validamos Cupo y Fecha
    $cupoLleno = $curso->total_solicitudes >= $curso->cupo_maximo;
    $registroVencido = $hoy->greaterThan($fechaLimite);
    
    // 3. Determinamos estado final
    $estaAbierto = !$cupoLleno && !$registroVencido;
    
    // 4. Color de la tarjeta (Verde=Abierto, Rojo=Cerrado)
    $estadoColor = $estaAbierto ? 'success' : 'danger';
    $estadoTexto = $estaAbierto ? 'ABIERTO' : 'CERRADO';
    
    if ($cupoLleno) $estadoTexto = 'CUPO LLENO';
    if ($registroVencido) $estadoTexto = 'FINALIZADO';
@endphp

<div class="col-12 col-md-6 col-lg-4 mb-4">
    {{-- Usamos la clase .hover-scale definida en Picade.css --}}
    <div class="card h-100 border-0 shadow-sm overflow-hidden hover-scale">
        
        {{-- ENCABEZADO: Color dinámico según estado --}}
        <div class="card-header border-0 d-flex justify-content-between align-items-center py-3 bg-{{ $estaAbierto ? 'light' : 'light' }}" 
             style="border-bottom: 4px solid var(--gob-{{ $estaAbierto ? 'verde' : 'guinda' }}) !important;">
            
            <h5 class="m-0 fw-bold text-dark">{{ $curso->folio }}</h5>
            
            <span class="badge bg-{{ $estadoColor }} px-3 py-2">
                {{ $estadoTexto }}
            </span>
        </div>

        <div class="card-body">
            {{-- TÍTULO DEL CURSO --}}
            <h6 class="fw-bold mb-1" style="color: var(--picade-guinda);">{{ $curso->tema }}</h6>
            <p class="small text-muted mb-3">
                <i class="bi bi-building me-1"></i> {{ $curso->gerencia }}
            </p>

            {{-- DATOS CLAVE (Grid visual) --}}
            <div class="small mb-3">
                <div class="d-flex justify-content-between mb-1 border-bottom pb-1">
                    <span class="fw-bold text-muted">Tipo:</span>
                    <span class="text-end">{{ $curso->tipo }}</span>
                </div>
                <div class="d-flex justify-content-between mb-1 border-bottom pb-1">
                    <span class="fw-bold text-muted">Solicitudes:</span>
                    <span class="text-primary fw-bold">Hasta {{ $fechaLimite->format('d/M') }}</span>
                </div>
                <div class="d-flex justify-content-between mb-1">
                    <span class="fw-bold text-muted">Instructor:</span>
                    <span class="text-end text-truncate" style="max-width: 150px;">{{ $curso->instructor }}</span>
                </div>
            </div>

            {{-- OBJETIVO (Truncado para uniformidad) --}}
            <div class="mb-3">
                <p class="fw-bold small mb-1">Objetivo:</p>
                <p class="small text-muted mb-0" style="display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden;">
                    {{ $curso->objetivo }}
                </p>
            </div>

            {{-- REQUISITOS --}}
            <div class="alert alert-light border p-2 mb-0">
                <p class="fw-bold small mb-1 text-dark"><i class="bi bi-exclamation-circle me-1 text-warning"></i> Requisitos:</p>
                <p class="small text-muted mb-0 lh-sm">{{ $curso->requisitos ?? 'Sin requisitos previos.' }}</p>
            </div>
        </div>

        {{-- FOOTER CON ESTADÍSTICAS Y ACCIÓN --}}
        <div class="card-footer bg-white border-top-0 pb-3 pt-0">
            <div class="d-flex justify-content-around text-center mb-3 pt-2 border-top">
                <div class="pt-2">
                    <i class="bi bi-people-fill text-secondary"></i>
                    <div class="small fw-bold">{{ $curso->total_solicitudes }} / {{ $curso->cupo_maximo }}</div>
                    <div class="text-muted" style="font-size: 0.65rem;">INSCRITOS</div>
                </div>
                <div class="vr opacity-25"></div>
                <div class="pt-2">
                    <i class="bi bi-eye-fill text-secondary"></i>
                    <div class="small fw-bold">{{ $curso->visitas ?? 0 }}</div>
                    <div class="text-muted" style="font-size: 0.65rem;">VISITAS</div>
                </div>
                <div class="vr opacity-25"></div>
                <div class="pt-2">
                    <i class="bi bi-file-earmark-check-fill text-secondary"></i>
                    <div class="small fw-bold">{{ $curso->constancias_entregadas ?? 0 }}</div>
                    <div class="text-muted" style="font-size: 0.65rem;">DC-3</div>
                </div>
            </div>

            <div class="d-grid">
                @if($estaAbierto)
                    {{-- Usamos la clase .btn-verde de Picade.css --}}
                    <a href="{{ route('cursos.inscripcion', $curso->id) }}" class="btn btn-verde btn-sm py-2">
                        <i class="bi bi-send-check me-2"></i> ENVIAR SOLICITUD
                    </a>
                @else
                    <button class="btn btn-secondary btn-sm py-2" disabled>
                        <i class="bi bi-lock-fill me-2"></i> REGISTRO CERRADO
                    </button>
                @endif
            </div>
        </div>
    </div>
</div>