<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class InfoPersonal extends Model
{
    protected $table      = 'Info_Personal';
    protected $primaryKey = 'Id_InfoPersonal';
    public $timestamps    = false;

    protected $fillable = [
        'Nombre',
        'Apellido_Paterno',
        'Apellido_Materno',
        'Fecha_Nacimiento',
        'Fecha_Ingreso',
        'Fk_Id_CatRegimen',
        'Fk_Id_CatPuesto',
        'Fk_Id_CatCT',
        'Fk_Id_CatDep',
        'Fk_Id_CatRegion',
        'Fk_Id_CatGeren',
        'Nivel',
        'Clasificacion',
        'Activo',
        'Fk_Id_Usuario_Created_By',
        'Fk_Id_Usuario_Updated_By',
    ];

    protected $casts = [
        'Fecha_Nacimiento' => 'date',
        'Fecha_Ingreso'    => 'date',
        'Activo'           => 'boolean',
        'created_at'       => 'datetime',
        'updated_at'       => 'datetime',
    ];

    // =========================================================================
    // RELACIONES
    // =========================================================================

    public function usuario()
    {
        return $this->hasOne(User::class, 'Fk_Id_InfoPersonal', 'Id_InfoPersonal');
    }

    public function regimen()
    {
        return $this->belongsTo(CatRol::class, 'Fk_Id_CatRegimen', 'Id_CatRegimen');
    }

    // Accessor: Nombre completo
    public function getNombreCompletoAttribute(): string
    {
        return trim("{$this->Nombre} {$this->Apellido_Paterno} {$this->Apellido_Materno}");
    }
}
