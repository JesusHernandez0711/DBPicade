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
        
        {{-- BOTÓN CORREGIDO: Usa la clase .btn-guinda definida arriba --}}
        <a href="{{ route('Usuarios.create') }}" class="btn btn-guinda shadow-sm btn-sm px-3 py-2">
            <i class="bi bi-person-plus-fill me-2"></i> Nuevo Usuario
        </a>
    </div>

    {{-- █ 2. BARRA DE HERRAMIENTAS (SINCRONIZACIÓN Y EXPANSIÓN PLATINUM) --}}
    <div class="card border-0 shadow-sm rounded-4 mb-4 bg-white">
        <div class="card-body p-2">
            {{-- Usamos flex-nowrap en pantallas medianas para evitar que el buscador caiga abajo --}}
            <form action="{{ route('Usuarios.index') }}" method="GET" class="row g-2 align-items-center flex-nowrap">
                
                {{-- 2.1. Buscador Elástico (Ocupa todo el espacio disponible) --}}
                <div class="col"> 
                    <div class="input-group input-group-lg rounded-pill overflow-hidden picade-search-group border-0">
                        <span class="input-group-text picade-search-icon">
                            <i class="bi bi-search"></i>
                        </span>
                        <input type="text" name="q" value="{{ request('q') }}" 
                            class="form-control picade-search-input py-2" 
                            placeholder="Buscar usuario por folio, nombre o correo electrónico..."
                            autocomplete="off"
                            style="font-size: 0.95rem;">
                        
                        @if(request('q'))
                            <a href="{{ route('Usuarios.index') }}" class="picade-clear-btn d-flex align-items-center" title="Limpiar búsqueda">
                                <i class="bi bi-x-circle-fill"></i>
                            </a>
                        @endif
                    </div>
                </div>

                {{-- 2.2. Separador Vertical (Encuadramiento de precisión) --}}
                <div class="col-auto d-none d-md-block px-1">
                    <div class="vr opacity-25" style="height: 30px;"></div>
                </div>

                {{-- 2.3. Grupo de Controles (Anclados a la derecha con tamaño automático) --}}
                <div class="col-auto d-flex align-items-center gap-3 pe-3">
                    
                    {{-- Ordenamiento (Texto en Sentence Case) --}}
                    <div class="d-flex align-items-center">
                        <span class="text-muted small pe-2" style="white-space: nowrap;">Ordenar por:</span>
                        <select name="sort" class="form-select border-0 bg-transparent shadow-none fw-bold text-dark small py-0" 
                                onchange="this.form.submit()" style="cursor: pointer; width: auto; font-size: 0.85rem;">
                            <option value="rol" {{ request('sort') == 'rol' || !request('sort') ? 'selected' : '' }}>Tipo de usuario</option>
                            <option value="folio_asc" {{ request('sort') == 'folio_asc' ? 'selected' : '' }}>Folio (0-9)</option>
                            <option value="folio_desc" {{ request('sort') == 'folio_desc' ? 'selected' : '' }}>Folio (9-0)</option>
                            <option value="nombre_az" {{ request('sort') == 'nombre_az' ? 'selected' : '' }}>Nombre (A-Z)</option>
                            <option value="nombre_za" {{ request('sort') == 'nombre_za' ? 'selected' : '' }}>Nombre (Z-A)</option>
                            <option value="activos" {{ request('sort') == 'activos' ? 'selected' : '' }}>Activos primero</option>
                            <option value="inactivos" {{ request('sort') == 'inactivos' ? 'selected' : '' }}>Inactivos primero</option>
                        </select>
                    </div>

                    {{-- Filtrado (Icono Guinda + Texto en Sentence Case) --}}
                    <div class="dropdown d-flex align-items-center">
                        <span class="text-muted small pe-2" style="white-space: nowrap;">Filtrar por:</span>
                        <button class="btn btn-white border rounded-3 btn-sm position-relative shadow-sm" 
                                type="button" data-bs-toggle="dropdown" data-bs-auto-close="outside">
                            {{-- Icono Guinda Relleno para mayor visibilidad --}}
                            <i class="bi bi-funnel-fill text-guinda"></i>
                            
                            @php 
                                $totalFiltros = (request('roles') ? count(request('roles')) : 0) + (request('estatus_filtro') ? count(request('estatus_filtro')) : 0);
                            @endphp
                            @if($totalFiltros > 0)
                                <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-danger" style="font-size: 0.55rem;">
                                    {{ $totalFiltros }}
                                </span>
                            @endif
                        </button>

                        <div class="dropdown-menu dropdown-menu-end shadow-lg border-0 p-3 mt-2 rounded-4" style="width: 280px;">
                            <h6 class="dropdown-header ps-0 text-dark fw-bold mb-2">Por roles</h6>
                            @foreach(['Administrador', 'Coordinador', 'Instructor', 'Participante'] as $rol)
                                <div class="form-check mb-2">
                                    <input class="form-check-input" type="checkbox" name="roles[]" value="{{ $rol }}" id="rol_{{ $rol }}"
                                        {{ is_array(request('roles')) && in_array($rol, request('roles')) ? 'checked' : '' }}>
                                    <label class="form-check-label small fw-medium" for="rol_{{ $rol }}">{{ $rol }}</label>
                                </div>
                            @endforeach
                            <div class="dropdown-divider my-3"></div>
                            <h6 class="dropdown-header ps-0 text-dark fw-bold mb-2">Por estatus</h6>
                            <div class="form-check mb-2">
                                <input class="form-check-input" type="checkbox" name="estatus_filtro[]" value="1" id="est_activo"
                                    {{ is_array(request('estatus_filtro')) && in_array('1', request('estatus_filtro')) ? 'checked' : '' }}>
                                <label class="form-check-label small fw-medium text-success" for="est_activo">Activos</label>
                            </div>
                            <div class="form-check mb-2">
                                <input class="form-check-input" type="checkbox" name="estatus_filtro[]" value="0" id="est_inactivo"
                                    {{ is_array(request('estatus_filtro')) && in_array('0', request('estatus_filtro')) ? 'checked' : '' }}>
                                <label class="form-check-label small fw-medium text-secondary" for="est_inactivo">Desactivados</label>
                            </div>
                            <div class="d-flex justify-content-between gap-2 mt-3">
                                <a href="{{ route('Usuarios.index') }}" class="btn btn-light border btn-sm flex-fill rounded-pill fw-bold" style="font-size: 0.75rem;">LIMPIAR</a>
                                <button type="submit" class="btn btn-guinda btn-sm flex-fill rounded-pill fw-bold" style="font-size: 0.75rem;">APLICAR</button>
                            </div>
                        </div>
                    </div>

                </div>
            </form>
        </div>
    </div>

    {{-- █ TARJETA DE CONTENIDO (DATA TABLE) --}}
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

                                {{-- 4. NIVEL DE ACCESO --}}
                                <td>
                                    @php
                                        $badgeClass = match($user->Rol_Usuario) {
                                            'Administrador' => 'bg-danger-subtle text-danger border-danger-subtle',
                                            'Instructor'    => 'bg-warning-subtle text-warning-emphasis border-warning-subtle',
                                            'Coordinador'   => 'bg-primary-subtle text-primary border-primary-subtle',
                                            default         => 'bg-light text-secondary border',
                                        };
                                    @endphp
                                    <span class="badge {{ $badgeClass }} border fw-bold rounded-pill px-3 py-1 text-uppercase" style="font-size: 0.7rem;">
                                        {{ $user->Rol_Usuario }}
                                    </span>
                                </td>

                                {{-- 5. CONTROL DE ESTATUS (SWITCH BAJA LÓGICA) --}}
                                <td class="text-center">
                                    @if($user->Id_Usuario == Auth::id())
                                        {{-- Caso: Es el mismo usuario administrador logueado --}}
                                        <div class="form-check form-switch d-flex justify-content-center" 
                                            data-bs-toggle="tooltip" 
                                            title="No puedes desactivar tu propia cuenta administrativa por seguridad.">
                                            <input class="form-check-input shadow-sm opacity-50" 
                                                type="checkbox" 
                                                role="switch" 
                                                checked 
                                                disabled 
                                                style="cursor: not-allowed; transform: scale(1.4);">
                                        </div>
                                    @else
                                        {{-- Caso: Son otros usuarios, se permite el control total --}}
                                        <form action="{{ route('Usuarios.Estatus', $user->Id_Usuario) }}" method="POST">
                                            @csrf 
                                            @method('PATCH')
                                            
                                            <input type="hidden" name="nuevo_estatus" value="{{ $user->Estatus_Usuario == 1 ? 0 : 1 }}">
                                            
                                            <div class="form-check form-switch d-flex justify-content-center">
                                                <input class="form-check-input shadow-sm" 
                                                    type="checkbox" 
                                                    role="switch" 
                                                    onchange="this.form.submit()" 
                                                    style="cursor: pointer; transform: scale(1.4);" 
                                                    data-bs-toggle="tooltip" 
                                                    data-bs-placement="top"
                                                    title="{{ $user->Estatus_Usuario == 1 ? 'Clic para Desactivar acceso' : 'Clic para Activar acceso' }}"
                                                    {{ $user->Estatus_Usuario ? 'checked' : '' }}>
                                            </div>
                                        </form>
                                    @endif
                                </td>

                                {{-- 6. ACCIONES CRUD --}}
<td class="pe-4 text-end">
    <div class="dropdown">
        <button class="btn btn-light btn-sm border rounded-circle" type="button" data-bs-toggle="dropdown">
            <i class="bi bi-three-dots-vertical"></i>
        </button>
        <ul class="dropdown-menu dropdown-menu-end shadow border-0">
            
            {{-- 1. VER EXPEDIENTE (Vía POST Blindado) --}}
            <li>
                {{-- Nota: action="{{ route('Usuarios.show') }}" SIN PARÁMETROS --}}
                <form action="{{ route('Usuarios.show') }}" method="POST">
                    @csrf 
                    {{-- Aquí encriptamos el ID para enviarlo oculto --}}
                    <input type="hidden" name="token_id" value="{{ Crypt::encryptString($user->Id_Usuario) }}">
                    
                    <button type="submit" class="dropdown-item py-2 w-100 text-start">
                        <i class="bi bi-eye text-primary me-2"></i> Ver Expediente
                    </button>
                </form>
            </li>

            {{-- 2. EDITAR DATOS (Vía POST Blindado) --}}
            <li>
                {{-- Nota: action="{{ route('Usuarios.edit') }}" SIN PARÁMETROS --}}
                <form action="{{ route('Usuarios.edit') }}" method="POST">
                    @csrf
                    <input type="hidden" name="token_id" value="{{ Crypt::encryptString($user->Id_Usuario) }}">
                    
                    <button type="submit" class="dropdown-item py-2 w-100 text-start">
                        <i class="bi bi-pencil-square text-warning me-2"></i> Editar Datos
                    </button>
                </form>
            </li>
            
            <li><hr class="dropdown-divider"></li>
            
            {{-- 3. ELIMINAR (Protegido) --}}
            <li>
                @if($user->Id_Usuario == Auth::id())
                    <button class="dropdown-item py-2 text-muted opacity-50" style="cursor: not-allowed;" title="No puedes eliminar tu propia cuenta.">
                        <i class="bi bi-trash3 me-2"></i> Eliminar (Protegido)
                    </button>
                @else
                    <form action="{{ route('Usuarios.destroy', $user->Id_Usuario) }}" method="POST" 
                          onsubmit="return confirm('⚠️ ALERTA FORENSE:\n\nEstás a punto de ELIMINAR FÍSICAMENTE este registro.\nEsta acción es IRREVERSIBLE.\n\n¿Estás seguro?');">
                        @csrf 
                        @method('DELETE')
                        <button type="submit" class="dropdown-item py-2 text-danger w-100 text-start">
                            <i class="bi bi-trash3 me-2"></i> Eliminar Definitivamente
                        </button>
                    </form>
                @endif
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
        

        {{--
           █ 4. PAGINACIÓN MANUAL (TU CÓDIGO HTML INYECTADO)
           ─────────────────────────────────────────────────────────────────────────
           Aquí está exactamente la estructura que pediste, pero le he metido lógica
           PHP (@if, @foreach) para que los números cambien de verdad.
        --}}
        <div class="card-footer bg-white border-top-0 py-3">
            <div class="d-flex justify-content-between align-items-center">
                {{-- Texto descriptivo en Español --}}
                <small class="text-muted">
                    Mostrando <strong>{{ $usuarios->firstItem() }}</strong> - <strong>{{ $usuarios->lastItem() }}</strong> de <strong>{{ $usuarios->total() }}</strong> registros
                </small>

                {{-- TU COMPONENTE DE PAGINACIÓN BOOTSTRAP --}}
                <nav aria-label="Page navigation example">
                    <ul class="pagination mb-0">
                        
                        {{-- Botón ANTERIOR («) --}}
                        <li class="page-item {{ $usuarios->onFirstPage() ? 'disabled' : '' }}">
                            <a class="page-link" href="{{ $usuarios->previousPageUrl() }}" aria-label="Previous">
                                <span aria-hidden="true">&laquo;</span>
                            </a>
                        </li>

                        {{-- Números de Página (Lógica de Ventana Deslizante Simplificada) --}}
                        @foreach(range(1, $usuarios->lastPage()) as $i)
                            @if($i >= $usuarios->currentPage() - 2 && $i <= $usuarios->currentPage() + 5)
                                <li class="page-item {{ ($usuarios->currentPage() == $i) ? 'active' : '' }}">
                                    <a class="page-link" href="{{ $usuarios->url($i) }}">{{ $i }}</a>
                                </li>
                            @endif
                        @endforeach

                        {{-- Botón SIGUIENTE (») --}}
                        <li class="page-item {{ $usuarios->hasMorePages() ? '' : 'disabled' }}">
                            <a class="page-link" href="{{ $usuarios->nextPageUrl() }}" aria-label="Next">
                                <span aria-hidden="true">&raquo;</span>
                            </a>
                        </li>
                    </ul>
                </nav>
                {{-- FIN DE TU COMPONENTE --}}

            </div>
        </div>
    </div>
@endsection