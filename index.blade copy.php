@extends('layouts.Panel')

@section('title', 'Gestión de Usuarios')
@section('header', 'Directorio de Personal')

@section('content')

    {{-- █ 1. ENCABEZADO Y BOTÓN DE CREACIÓN --}}
    <div class="d-flex justify-content-between align-items-end mb-4">
        <div>
            <h4 class="mb-1 fw-bold text-dark">Colaboradores Registrados</h4>
            <p class="text-muted small mb-0">
                Gestión integral de acceso y perfiles del sistema PICADE.
                <span class="badge bg-light text-secondary border ms-2">{{ $usuarios->total() }} Registros</span>
            </p>
        </div>
        <a href="{{ route('usuarios.create') }}" class="btn btn-guinda shadow-sm btn-sm px-3 py-2">
            <i class="bi bi-person-plus-fill me-2"></i> Nuevo Usuario
        </a>
    </div>

    {{-- █ 2. BARRA DE HERRAMIENTAS (BUSCADOR Y FILTROS) --}}
    <div class="card border-0 shadow-sm rounded-3 mb-4 bg-white">
        <div class="card-body p-2">
            <form action="{{ route('usuarios.index') }}" method="GET" class="row g-2 align-items-center">
                
                {{-- Input de Búsqueda --}}
                <div class="col-12 col-md-6 col-lg-7">
                    <div class="input-group">
                        <span class="input-group-text bg-transparent border-0 ps-3 text-muted">
                            <i class="bi bi-search"></i>
                        </span>
                        <input type="text" name="q" value="{{ request('q') }}" 
                               class="form-control border-0 bg-transparent shadow-none ps-1" 
                               placeholder="Buscar usuario por folio, nombre o correo electrónico..."
                               style="font-size: 0.9rem;">
                        @if(request('q'))
                            <a href="{{ route('usuarios.index') }}" class="btn btn-link text-muted text-decoration-none" title="Limpiar búsqueda">
                                <i class="bi bi-x-lg"></i>
                            </a>
                        @endif
                    </div>
                </div>

                {{-- Separador Vertical (Solo Desktop) --}}
                <div class="col-auto d-none d-md-block">
                    <div class="vr h-100 opacity-25"></div>
                </div>

                {{-- Select de Ordenamiento --}}
                <div class="col-6 col-md-3 col-lg-3">
                    <div class="input-group input-group-sm">
                        <span class="input-group-text bg-transparent border-0 text-muted small">Ordenar por:</span>
                        <select name="sort" class="form-select border-0 bg-transparent shadow-none fw-bold text-dark small" onchange="this.form.submit()">
                            <option value="folio_asc" {{ request('sort') == 'folio_asc' ? 'selected' : '' }}>Folio (0-9)</option>
                            <option value="folio_desc" {{ request('sort') == 'folio_desc' ? 'selected' : '' }}>Folio (9-0)</option>
                            <option value="nombre_az" {{ request('sort') == 'nombre_az' ? 'selected' : '' }}>Nombre (A-Z)</option>
                            <option value="nombre_za" {{ request('sort') == 'nombre_za' ? 'selected' : '' }}>Nombre (Z-A)</option>
                            <option value="rol" {{ request('sort') == 'rol' ? 'selected' : '' }}>Tipo Usuario</option>
                            <option value="estatus" {{ request('sort') == 'estatus' ? 'selected' : '' }}>Estatus</option>
                        </select>
                    </div>
                </div>

                {{-- Botón de Filtrar (Visual) --}}
                <div class="col-auto ms-auto">
                    <button type="submit" class="btn btn-light border btn-sm rounded-2 text-muted" title="Aplicar Filtros">
                        <i class="bi bi-funnel"></i>
                    </button>
                </div>
            </form>
        </div>
    </div>

    {{-- █ 3. TABLA DE DATOS --}}
    <div class="card border-0 shadow-sm rounded-4 overflow-hidden">
        <div class="card-body p-0">
            <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                    <thead class="bg-light border-bottom">
                        <tr>
                            <th class="ps-4 py-3 text-secondary text-uppercase small fw-bold" style="width: 5%;">#</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 15%;">Ficha</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 35%;">Colaborador</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 15%;">Rol</th>
                            
                            {{-- Header Estatus con Tooltip Informativo --}}
                            <th class="py-3 text-secondary text-uppercase small fw-bold text-center" style="width: 15%;">
                                Estatus
                                <span class="ms-1" data-bs-toggle="tooltip" data-bs-placement="top" 
                                      title="Interruptor de acceso. Si se apaga, el usuario no podrá iniciar sesión, pero su historial se conserva.">
                                    <i class="bi bi-info-circle text-info" style="cursor: help;"></i>
                                </span>
                            </th>
                            
                            {{-- Header Acciones con Tooltip Informativo --}}
                            <th class="pe-4 py-3 text-secondary text-uppercase small fw-bold text-end" style="width: 15%;">
                                Acciones
                                <span class="ms-1" data-bs-toggle="tooltip" data-bs-placement="top" 
                                      title="Opciones de gestión. 'Eliminar' es una acción destructiva e irreversible.">
                                    <i class="bi bi-info-circle text-info" style="cursor: help;"></i>
                                </span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($usuarios as $user)
                            <tr class="group-hover-effect">
                                {{-- 1. CONSECUTIVO (Cálculo real basado en paginación) --}}
                                <td class="ps-4 fw-bold text-muted small">
                                    {{ $usuarios->firstItem() + $loop->index }}
                                </td>

                                {{-- 2. FICHA / FOLIO --}}
                                <td>
                                    <div class="d-flex align-items-center">
                                        <i class="bi bi-card-heading text-secondary me-2"></i>
                                        <span class="fw-bold text-dark">{{ $user->Ficha_Usuario }}</span>
                                    </div>
                                </td>

                                {{-- 3. PERFIL COLABORADOR --}}
                                <td>
                                    <div class="d-flex align-items-center">
                                        {{-- Avatar --}}
                                        <div class="avatar rounded-circle bg-light border d-flex justify-content-center align-items-center me-3 flex-shrink-0" 
                                             style="width: 38px; height: 38px; overflow: hidden;">
                                            @if($user->Foto_Perfil)
                                                <img src="{{ $user->Foto_Perfil }}" alt="Img" class="w-100 h-100 object-fit-cover">
                                            @else
                                                <i class="bi bi-person text-secondary fs-5"></i>
                                            @endif
                                        </div>
                                        {{-- Datos --}}
                                        <div class="d-flex flex-column" style="line-height: 1.2;">
                                            <span class="fw-bold text-dark" style="font-size: 0.85rem;">
                                                {{ $user->Nombre_Completo }}
                                            </span>
                                            <span class="text-muted small" style="font-size: 0.75rem;">
                                                {{ strtolower($user->Email_Usuario) }}
                                            </span>
                                        </div>
                                    </div>
                                </td>

                                {{-- 4. ROL --}}
                                <td>
                                    @php
                                        $badgeClass = match($user->Rol_Usuario) {
                                            'Administrador' => 'bg-danger-subtle text-danger border-danger-subtle',
                                            'Instructor'    => 'bg-warning-subtle text-warning-emphasis border-warning-subtle',
                                            'Coordinador'   => 'bg-primary-subtle text-primary border-primary-subtle',
                                            default         => 'bg-light text-secondary border',
                                        };
                                    @endphp
                                    <span class="badge {{ $badgeClass }} border fw-bold rounded-pill px-3 py-1">
                                        {{ $user->Rol_Usuario }}
                                    </span>
                                </td>

                                {{-- 5. SWITCH ESTATUS --}}
                                <td class="text-center">
                                    <form action="{{ route('usuarios.estatus', $user->Id_Usuario) }}" method="POST">
                                        @csrf
                                        @method('PATCH')
                                        <input type="hidden" name="nuevo_estatus" value="{{ $user->Estatus_Usuario == 1 ? 0 : 1 }}">
                                        
                                        <div class="form-check form-switch d-flex justify-content-center">
                                            <input class="form-check-input" type="checkbox" role="switch" 
                                                   onchange="this.form.submit()" 
                                                   style="cursor: pointer; transform: scale(1.2);"
                                                   {{ $user->Estatus_Usuario ? 'checked' : '' }}>
                                        </div>
                                    </form>
                                </td>

                                {{-- 6. MENÚ DE ACCIONES --}}
                                <td class="pe-4 text-end">
                                    <div class="dropdown">
                                        <button class="btn btn-light btn-sm border rounded-circle shadow-sm" type="button" data-bs-toggle="dropdown" aria-expanded="false">
                                            <i class="bi bi-three-dots-vertical text-secondary"></i>
                                        </button>
                                        <ul class="dropdown-menu dropdown-menu-end shadow-sm border-0 rounded-3 p-1">
                                            <li>
                                                <a class="dropdown-item py-2 rounded-2 small" href="{{ route('usuarios.show', $user->Id_Usuario) }}">
                                                    <i class="bi bi-eye text-primary me-2"></i> Ver Expediente
                                                </a>
                                            </li>
                                            <li>
                                                <a class="dropdown-item py-2 rounded-2 small" href="{{ route('usuarios.edit', $user->Id_Usuario) }}">
                                                    <i class="bi bi-pencil-square text-warning me-2"></i> Editar Datos
                                                </a>
                                            </li>
                                            <li><hr class="dropdown-divider my-1"></li>
                                            <li>
                                                <form action="{{ route('usuarios.destroy', $user->Id_Usuario) }}" method="POST" onsubmit="return confirm('⚠️ ALERTA FORENSE:\n\nEstás a punto de ELIMINAR FÍSICAMENTE este registro.\nEsta acción es IRREVERSIBLE y borrará todo el historial del usuario.\n\n¿Deseas continuar?');">
                                                    @csrf
                                                    @method('DELETE')
                                                    <button type="submit" class="dropdown-item py-2 rounded-2 small text-danger fw-bold">
                                                        <i class="bi bi-trash3 me-2"></i> Eliminar
                                                    </button>
                                                </form>
                                            </li>
                                        </ul>
                                    </div>
                                </td>
                            </tr>
                        @empty
                            <tr>
                                <td colspan="6" class="text-center py-5">
                                    <div class="d-flex flex-column align-items-center justify-content-center opacity-50">
                                        <i class="bi bi-search display-1 text-muted mb-3"></i>
                                        <h5 class="text-secondary fw-bold">Sin resultados</h5>
                                        <p class="text-muted small">No se encontraron usuarios con los criterios de búsqueda.</p>
                                        <a href="{{ route('usuarios.index') }}" class="btn btn-outline-secondary btn-sm mt-2">
                                            Limpiar filtros
                                        </a>
                                    </div>
                                </td>
                            </tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>
        
        {{-- PAGINACIÓN --}}
        <div class="card-footer bg-white border-top-0 py-3">
            <div class="d-flex justify-content-between align-items-center">
                <small class="text-muted">
                    Mostrando del {{ $usuarios->firstItem() }} al {{ $usuarios->lastItem() }} de {{ $usuarios->total() }} registros.
                </small>
                <div>
                    {{ $usuarios->links() }}
                </div>
            </div>
        </div>
    </div>

    {{-- Script para inicializar Tooltips --}}
    @push('scripts')
    <script>
        document.addEventListener("DOMContentLoaded", function() {
            var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
            var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
                return new bootstrap.Tooltip(tooltipTriggerEl)
            })
        });
    </script>
    @endpush

@endsection