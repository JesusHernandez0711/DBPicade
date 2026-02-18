{{-- resources/views/panel/admin/usuarios/edit.blade.php --}}
@extends('layouts.Panel')
@section('title', 'Editar Usuario')

@section('content')
<form action="{{ route('Usuarios.update', $usuario->Id_Usuario) }}" method="POST" enctype="multipart/form-data">
    @csrf
    @method('PUT') {{-- Importante para Update --}}

    <div class="d-flex justify-content-between align-items-center mb-4">
        <h3>Editar Colaborador: {{ $usuario->Nombre }}</h3>
        <button type="submit" class="btn btn-warning shadow rounded-pill px-4">
            <i class="bi bi-save me-2"></i> Guardar Cambios
        </button>
    </div>

    {{-- INCLUIMOS EL FORMULARIO PARCIAL --}}
    @include('panel.admin.usuarios.partials.form', ['readonly' => false])

</form>
@endsection