<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

/**
 * Tabla de configuraciones del sistema.
 * Permite al admin cambiar parámetros desde el panel
 * sin tocar código ni archivos .env.
 *
 * Uso principal: imagen de fondo del login (configurable).
 */
return new class extends Migration
{
    public function up(): void
    {
        // Solo crear si no existe (la BD PICADE ya puede tener tablas propias)
        if (!Schema::hasTable('configuraciones')) {
            Schema::create('configuraciones', function (Blueprint $table) {
                $table->id();
                $table->string('clave', 100)->unique();
                $table->text('valor')->nullable();
                $table->string('descripcion', 255)->nullable();
                $table->timestamps();
            });

            // Seed: valor por defecto de la imagen de fondo del login
            DB::table('configuraciones')->insert([
                [
                    'clave'       => 'login_bg_image',
                    'valor'       => null, // NULL = usa default en public/images/picade-bg-default.jpg
                    'descripcion' => 'Ruta relativa de la imagen de fondo del login (storage). NULL = imagen por defecto.',
                    'created_at'  => now(),
                    'updated_at'  => now(),
                ],
                [
                    'clave'       => 'nombre_sistema',
                    'valor'       => 'PICADE',
                    'descripcion' => 'Nombre del sistema mostrado en el login y encabezados.',
                    'created_at'  => now(),
                    'updated_at'  => now(),
                ],
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('configuraciones');
    }
};
