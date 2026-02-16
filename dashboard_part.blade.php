{{-- resources/views/dashboard_general.blade.php --}}
@extends('layouts.Panel')

@section('title', 'Mi Tablero')

@section('content')
<div class="container-fluid">
    <div class="row g-4 mb-4">
        {{-- 1. TARJETA: OFERTA ACADÉMICA (Visible para TODOS) --}}
        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-white" 
                 style="background: linear-gradient(135deg, #1e5b4f, #1e8b75);">
                <div class="card-body p-4 position-relative z-1">
                    <div class="d-flex justify-content-between align-items-start">
                        <div>
                            <div class="text-uppercase fw-bold opacity-75 small mb-1">CAPACITACIONES</div>
                            <h3 class="fw-bold mb-2">Oferta</h3>
                            <p class="small opacity-75 mb-0 lh-sm">Inscríbete a los cursos disponibles para este ciclo.</p>
                        </div>
                    </div>
                    <i class="bi bi-journal-bookmark-fill position-absolute opacity-25" 
                       style="font-size: 7rem; bottom: -15px; right: -15px; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="{{ route('cursos.oferta') }}" class="stretched-link"></a>
            </div>
        </div>

        {{-- 2. TARJETA: MI KÁRDEX (Visible para TODOS) --}}
        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-dark" 
                 style="background: linear-gradient(135deg, #ffc107, #f1c40f);">
                <div class="card-body p-4 position-relative z-1">
                    <div class="d-flex justify-content-between align-items-start">
                        <div>
                            <div class="text-uppercase fw-bold opacity-50 small mb-1">MI KÁRDEX</div>
                            <h3 class="fw-bold mb-2">Historial</h3>
                            <p class="small opacity-75 mb-0 lh-sm">Calificaciones, constancias DC-3 y registros.</p>
                        </div>
                    </div>
                    <i class="bi bi-mortarboard-fill position-absolute opacity-25" 
                       style="font-size: 7rem; bottom: -15px; right: -15px; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="{{ route('perfil.kardex') }}" class="stretched-link"></a>
            </div>
        </div>

        {{-- 3. TARJETA: DOCENCIA (Solo para Instructor, Coordinador y Admin) --}}
        @if(in_array(Auth::user()->Fk_Rol, [1, 2, 3]))
        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-white" 
                 style="background: linear-gradient(135deg, #dc3545, #e74c3c);">
                <div class="card-body p-4 position-relative z-1">
                    <div class="d-flex justify-content-between align-items-start">
                        <div>
                            <div class="text-uppercase fw-bold opacity-75 small mb-1">DOCENCIA</div>
                            <h3 class="fw-bold mb-2">Instructor</h3>
                            <p class="small opacity-75 mb-0 lh-sm">Captura de notas y control de asistencia de tus grupos.</p>
                        </div>
                    </div>
                    <i class="bi bi-person-video3 position-absolute opacity-25" 
                       style="font-size: 7rem; bottom: -15px; right: -15px; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="{{ route('docencia.index') }}" class="stretched-link"></a>
            </div>
        </div>
        @endif

        {{-- 4. TARJETA: GESTIÓN (Solo para Coordinador y Admin) --}}
        @if(in_array(Auth::user()->Fk_Rol, [1, 2]))
        <div class="col-sm-6 col-xl-3">
            <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-white" 
                 style="background: linear-gradient(135deg, #0d6efd, #3498db);">
                <div class="card-body p-4 position-relative z-1">
                    <div class="d-flex justify-content-between align-items-start">
                        <div>
                            <div class="text-uppercase fw-bold opacity-75 small mb-1">ADMINISTRACIÓN</div>
                            <h3 class="fw-bold mb-2">Gestión</h3>
                            <p class="small opacity-75 mb-0 lh-sm">Programación, catálogos y reportes maestros.</p>
                        </div>
                    </div>
                    <i class="bi bi-easel-fill position-absolute opacity-25" 
                       style="font-size: 7rem; bottom: -15px; right: -15px; transform: rotate(-10deg); z-index: 0;"></i>
                </div>
                <a href="{{ route('gestion.index') }}" class="stretched-link"></a>
            </div>
        </div>
        @endif
    </div>

    {{-- Buscador Global para todos --}}
    <div class="row">
        <div class="col-12">
            <div class="card border-0 shadow-sm">
                <div class="card-body p-4 text-center">
                    <h5 class="fw-bold mb-3"><i class="bi bi-search me-2 text-primary"></i>¿Buscas algo específico?</h5>
                    <form action="#" method="GET">
                        <div class="input-group input-group-lg">
                            <input type="text" class="form-control bg-light border-0" placeholder="Escribe el folio de un curso o tema...">
                            <button class="btn btn-guinda px-5" type="submit">BUSCAR</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>
@endsection