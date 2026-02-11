<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CatRol extends Model
{
    protected $table      = 'Cat_Roles';
    protected $primaryKey = 'Id_Rol';
    public $timestamps    = false;

    protected $fillable = [
        'Codigo',
        'Nombre',
        'Descripcion',
        'Activo',
    ];

    protected $casts = [
        'Activo' => 'boolean',
    ];

    public function usuarios()
    {
        return $this->hasMany(User::class, 'Fk_Rol', 'Id_Rol');
    }
}
