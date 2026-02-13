@extends('layouts.Panel')

@section('title', 'Gestión de Usuarios')
@section('header', 'Directorio de Personal')

@section('content')

    {{-- █ BARRA DE HERRAMIENTAS SUPERIOR --}}
    <div class="d-flex justify-content-between align-items-center mb-4">
        <div>
            <h4 class="mb-1 fw-bold text-dark">Colaboradores Registrados</h4>
            <p class="text-muted small mb-0">
                Gestión integral de acceso y perfiles del sistema PICADE.
            </p>
        </div>
        <div>
            {{-- Botón para Crear Nuevo Usuario --}}
            <a href="{{ route('usuarios.create') }}" class="btn btn-guinda shadow-sm">
                <i class="bi bi-person-plus-fill me-2"></i> Nuevo Usuario
            </a>
        </div>
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

    {{-- █ TARJETA DE CONTENIDO (DATA TABLE) --}}
    <div class="card border-0 shadow-sm rounded-4">
        <div class="card-body p-0">
            <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                    <thead class="bg-light">
                        <tr>
                            <th class="ps-4 py-3 text-secondary text-uppercase small fw-bold" style="width: 5%;">#</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 35%;">Colaborador</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 15%;">Ficha</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 15%;">Rol</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold text-center" style="width: 15%;">Estatus</th>
                            <th class="pe-4 py-3 text-secondary text-uppercase small fw-bold text-end" style="width: 15%;">Acciones</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($usuarios as $user)
                            <tr>
                                {{-- 1. ID / FOTO --}}
                                <td class="ps-4">
                                    <div class="avatar rounded-circle bg-light border d-flex justify-content-center align-items-center" 
                                         style="width: 40px; height: 40px; overflow: hidden;">
                                        @if($user->Foto_Perfil)
                                            <img src="{{ $user->Foto_Perfil }}" alt="Avatar" class="w-100 h-100 object-fit-cover">
                                        @else
                                            <i class="bi bi-person-fill text-secondary fs-5"></i>
                                        @endif
                                    </div>
                                </td>

                                {{-- 2. IDENTIDAD HUMANA --}}
                                <td>
                                    <div class="d-flex flex-column">
                                        <span class="fw-bold text-dark">{{ $user->Nombre_Completo }}</span>
                                        <span class="text-muted small">{{ $user->Email_Usuario }}</span>
                                    </div>
                                </td>

                                {{-- 3. IDENTIDAD CORPORATIVA --}}
                                <td>
                                    <span class="badge bg-light text-dark border">
                                        <i class="bi bi-card-heading me-1"></i> {{ $user->Ficha_Usuario }}
                                    </span>
                                </td>

                                {{-- 4. NIVEL DE ACCESO --}}
                                <td>
                                    @php
                                        // Lógica visual para roles (puedes ajustar colores)
                                        $badgeColor = match($user->Rol_Usuario) {
                                            'Administrador' => 'bg-danger-subtle text-danger',
                                            'Instructor'    => 'bg-warning-subtle text-dark',
                                            default         => 'bg-info-subtle text-primary',
                                        };
                                    @endphp
                                    <span class="badge {{ $badgeColor }} rounded-pill px-3">
                                        {{ $user->Rol_Usuario }}
                                    </span>
                                </td>

                                {{-- 5. CONTROL DE ESTATUS (SWITCH BAJA LÓGICA) --}}
                                <td class="text-center">
                                    <form action="{{ route('usuarios.estatus', $user->Id_Usuario) }}" method="POST" class="d-inline-block">
                                        @csrf
                                        @method('PATCH')
                                        {{-- 
                                            Lógica: Enviamos el valor OPUESTO al actual.
                                            Si es 1 (Activo), enviamos 0. Si es 0 (Inactivo), enviamos 1.
                                        --}}
                                        <input type="hidden" name="nuevo_estatus" value="{{ $user->Estatus_Usuario == 1 ? 0 : 1 }}">
                                        
                                        <button type="submit" 
                                                class="btn btn-sm border-0 {{ $user->Estatus_Usuario ? 'text-success' : 'text-secondary' }}"
                                                data-bs-toggle="tooltip" 
                                                title="{{ $user->Estatus_Usuario ? 'Clic para Desactivar' : 'Clic para Reactivar' }}">
                                            
                                            @if($user->Estatus_Usuario)
                                                <i class="bi bi-toggle-on fs-4"></i>
                                            @else
                                                <i class="bi bi-toggle-off fs-4"></i>
                                            @endif
                                        </button>
                                    </form>
                                </td>

                                {{-- 6. ACCIONES CRUD --}}
                                <td class="pe-4 text-end">
                                    <div class="dropdown">
                                        <button class="btn btn-light btn-sm border rounded-circle" type="button" data-bs-toggle="dropdown">
                                            <i class="bi bi-three-dots-vertical"></i>
                                        </button>
                                        <ul class="dropdown-menu dropdown-menu-end shadow border-0">
                                            <li>
                                                <a class="dropdown-item py-2" href="{{ route('usuarios.show', $user->Id_Usuario) }}">
                                                    <i class="bi bi-eye text-primary me-2"></i> Ver Expediente
                                                </a>
                                            </li>
                                            <li>
                                                <a class="dropdown-item py-2" href="{{ route('usuarios.edit', $user->Id_Usuario) }}">
                                                    <i class="bi bi-pencil-square text-warning me-2"></i> Editar Datos
                                                </a>
                                            </li>
                                            <li><hr class="dropdown-divider"></li>
                                            <li>
                                                {{-- BOTÓN DE BORRADO FÍSICO (CUIDADO) --}}
                                                <form action="{{ route('usuarios.destroy', $user->Id_Usuario) }}" method="POST" onsubmit="return confirm('⚠️ ALERTA FORENSE:\n\nEstás a punto de ELIMINAR FÍSICAMENTE este registro.\nEsta acción es IRREVERSIBLE y borrará todo el historial del usuario.\n\n¿Estás seguro?');">
                                                    @csrf
                                                    @method('DELETE')
                                                    <button type="submit" class="dropdown-item py-2 text-danger">
                                                        <i class="bi bi-trash3 me-2"></i> Eliminar Definitivamente
                                                    </button>
                                                </form>
                                            </li>
                                        </ul>
                                    </div>
                                </td>
                            </tr>
                        @empty
                            {{-- ESTADO VACÍO --}}
                            <tr>
                                <td colspan="6" class="text-center py-5">
                                    <div class="d-flex flex-column align-items-center justify-content-center opacity-50">
                                        <i class="bi bi-people display-4 mb-3"></i>
                                        <h5>No se encontraron usuarios</h5>
                                        <p class="small">La base de datos está vacía o no hay coincidencias.</p>
                                    </div>
                                </td>
                            </tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>
        
        {{-- PAGINACIÓN --}}
        <div class="card-footer bg-white border-0 py-3">
            <div class="d-flex justify-content-center">
                {{ $usuarios->links() }}
            </div>
        </div>
    </div>

@endsection