{{-- resources/views/panel/admin/usuarios/show.blade.php --}}
@extends('layouts.Panel')
@section('title', 'Expediente del Usuario')

@section('content')

{{-- 1. INFORMACIÓN PERSONAL (Solo Lectura) --}}
<div class="d-flex justify-content-between align-items-center mb-4">
    <h3>Expediente Digital</h3>
    {{-- Botón para ir a editar (usando el POST blindado si quieres, o un simple redirect en JS) --}}
    <form action="{{ route('Usuarios.edit') }}" method="POST">
        @csrf
        <input type="hidden" name="token_id" value="{{ Crypt::encryptString($usuario->Id_Usuario) }}">
        <button type="submit" class="btn btn-primary rounded-pill px-4">
            <i class="bi bi-pencil-square me-2"></i> Editar Datos
        </button>
    </form>
</div>

{{-- Reutilizamos el form pero bloqueado --}}
@include('panel.admin.usuarios.partials.form', ['readonly' => true])

<hr class="my-5">

{{-- 2. HISTORIAL ACADÉMICO (ADMINISTRABLE) --}}
<div class="card border-0 shadow-sm rounded-4">
    <div class="card-header bg-white py-3">
        <h5 class="mb-0 fw-bold"><i class="bi bi-journal-text me-2 text-guinda"></i>Historial de Capacitaciones</h5>
    </div>
    <div class="card-body p-0">
        <div class="table-responsive">
            <table class="table table-hover align-middle mb-0">
                <thead class="bg-light">
                    <tr>
                        <th class="ps-4">Curso</th>
                        <th>Fecha</th>
                        <th class="text-center">Asistencia</th>
                        <th class="text-center">Calificación</th>
                        <th class="text-center">Estatus</th>
                        <th class="text-end pe-4">Acciones Admin</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($kardex as $curso)
                    <tr>
                        <td class="ps-4">
                            <div class="fw-bold">{{ $curso->Tema_Curso }}</div>
                            <small class="text-muted">{{ $curso->Folio_Curso }}</small>
                        </td>
                        <td>
                            <small>{{ $curso->Fecha_Inicio }} <br> {{ $curso->Fecha_Fin }}</small>
                        </td>
                        <td class="text-center">{{ $curso->Porcentaje_Asistencia ?? '-' }}%</td>
                        <td class="text-center fw-bold">{{ $curso->Calificacion_Numerica ?? '-' }}</td>
                        <td class="text-center">
                            {{-- Badge de Estatus --}}
                            <span class="badge bg-{{ $curso->Id_Estatus_Participante == 3 ? 'success' : ($curso->Id_Estatus_Participante == 5 ? 'danger' : 'secondary') }}">
                                {{ $curso->Estatus_Participante }}
                            </span>
                        </td>
                        <td class="text-end pe-4">
                            <div class="dropdown">
                                <button class="btn btn-sm btn-light border" data-bs-toggle="dropdown">
                                    <i class="bi bi-gear-fill"></i>
                                </button>
                                <ul class="dropdown-menu dropdown-menu-end">
                                    {{-- EDITAR EVALUACIÓN (Llama a SP_EditarParticipanteCapacitacion) --}}
                                    <li>
                                        <button class="dropdown-item" 
                                            onclick="abrirModalEvaluacion({{ json_encode($curso) }})">
                                            <i class="bi bi-pencil me-2 text-warning"></i> Corregir Calificación
                                        </button>
                                    </li>
                                    {{-- CAMBIAR ESTATUS (Llama a SP_CambiarEstatusParticipanteCapacitacion) --}}
                                    <li>
                                        <button class="dropdown-item text-danger" 
                                            onclick="abrirModalEstatus({{ json_encode($curso) }})">
                                            <i class="bi bi-person-x me-2"></i> Baja / Reinscribir
                                        </button>
                                    </li>
                                </ul>
                            </div>
                        </td>
                    </tr>
                    @empty
                    <tr><td colspan="6" class="text-center py-4">Sin historial académico.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>

{{-- MODAL 1: EDICIÓN DE RESULTADOS (SP_EditarParticipanteCapacitacion) --}}
<div class="modal fade" id="modalEvaluacion" tabindex="-1">
    <div class="modal-dialog">
        <form action="{{ route('admin.curso.updateParticipante') }}" method="POST" class="modal-content">
            @csrf
            @method('PUT')
            <input type="hidden" name="id_registro" id="eval_id_registro">
            
            <div class="modal-header">
                <h5 class="modal-title">Corregir Evaluación</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <div class="mb-3">
                    <label class="form-label">Calificación (0-100)</label>
                    <input type="number" step="0.01" name="calificacion" id="eval_calificacion" class="form-control">
                </div>
                <div class="mb-3">
                    <label class="form-label">Asistencia (%)</label>
                    <input type="number" step="0.01" name="asistencia" id="eval_asistencia" class="form-control">
                </div>
                <div class="mb-3">
                    <label class="form-label">Justificación (Auditoría)</label>
                    <textarea name="justificacion" class="form-control" rows="2" required placeholder="Motivo del cambio..."></textarea>
                </div>
            </div>
            <div class="modal-footer">
                <button type="submit" class="btn btn-primary">Guardar Cambios</button>
            </div>
        </form>
    </div>
</div>

{{-- MODAL 2: CAMBIO DE ESTATUS (SP_CambiarEstatusParticipanteCapacitacion) --}}
<div class="modal fade" id="modalEstatus" tabindex="-1">
    <div class="modal-dialog">
        <form action="{{ route('admin.curso.toggleEstatus') }}" method="POST" class="modal-content">
            @csrf
            @method('PATCH')
            <input type="hidden" name="id_registro" id="est_id_registro">
            
            <div class="modal-header">
                <h5 class="modal-title">Cambio Administrativo</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <p>Acción sobre: <strong id="est_curso_nombre"></strong></p>
                <div class="mb-3">
                    <label class="form-label">Nuevo Estatus</label>
                    <select name="nuevo_estatus" class="form-select" id="est_select">
                        <option value="1">INSCRITO (Activo)</option>
                        <option value="5">BAJA (Cancelado)</option>
                    </select>
                </div>
                <div class="mb-3">
                    <label class="form-label">Motivo (Obligatorio)</label>
                    <textarea name="motivo" class="form-control" rows="2" required></textarea>
                </div>
            </div>
            <div class="modal-footer">
                <button type="submit" class="btn btn-danger">Aplicar Cambio</button>
            </div>
        </form>
    </div>
</div>

<script>
    function abrirModalEvaluacion(curso) {
        document.getElementById('eval_id_registro').value = curso.Id_Detalle_de_Capacitacion; // Ojo: Revisar si es ID de inscripción
        document.getElementById('eval_calificacion').value = curso.Calificacion_Numerica;
        document.getElementById('eval_asistencia').value = curso.Porcentaje_Asistencia;
        new bootstrap.Modal(document.getElementById('modalEvaluacion')).show();
    }

    function abrirModalEstatus(curso) {
        document.getElementById('est_id_registro').value = curso.Id_Detalle_de_Capacitacion; 
        document.getElementById('est_curso_nombre').innerText = curso.Tema_Curso;
        document.getElementById('est_select').value = (curso.Id_Estatus_Participante == 5) ? 1 : 5; // Sugerir lo contrario
        new bootstrap.Modal(document.getElementById('modalEstatus')).show();
    }
</script>

@endsection