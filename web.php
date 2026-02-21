    <?php
    /**
     * █ SISTEMA DE RUTAS MAESTRAS - PLATAFORMA PICADE
     * ─────────────────────────────────────────────────────────────────────────────────────────────
     * @project     PICADE (Plataforma Integral de Capacitación y Desarrollo)
     * @version     4.0.0 (Build: Platinum Forensic Standard)
     * @security    ISO/IEC 27001 - Layer 7 (Application Routing Protection)
     * @author      División de Desarrollo Tecnológico & Seguridad de la Información
     * * █ FILOSOFÍA DE ENRUTAMIENTO:
     * Implementamos un modelo Híbrido:
     * 1. RESTFUL RESOURCES: Para gestión masiva y administrativa (CRUD).
     * 2. EXPLICIT CONTROLLER GROUPS: Para flujos de identidad sensible (IMC) y Dashboard.
     * 3. AJAX/API PREFIXING: Para servicios de hidratación reactiva de formularios.
     */

    use Illuminate\Support\Facades\Route;
    use Illuminate\Support\Facades\Auth;
    use App\Http\Controllers\DashboardController;
    use App\Http\Controllers\UsuarioController;
    use App\Http\Controllers\CatalogoController;

    /*
    |--------------------------------------------------------------------------
    | 1. GESTIÓN DE ACCESO INICIAL (GATEWAY)
    |--------------------------------------------------------------------------
    | Redirección inteligente basada en estado de sesión.
    */
    Route::get('/', function () {
        return Auth::check() ? redirect('/Dashboard') : redirect('/login');
    });

    /** * RUTAS DE AUTENTICACIÓN (Librería UI) 
     * Implementa el protocolo de verificación de doble paso vía Email.
     */
    Auth::routes(['verify' => true]);

    /*
    |==========================================================================
    | 2. ECOSISTEMA PROTEGIDO (CERTIFIED AREA)
    |==========================================================================
    | Barrera de Seguridad: Requiere Token de Sesión + Email Verificado.
    */
    Route::middleware(['auth', 'verified'])->group(function () {

    /* --------------------------------------------------------------------
       A. MÓDULO DE DASHBOARD (ORQUESTADOR OPERATIVO)
       ────────────────────────────────────────────────────────────────────
       Mapea las vistas de control y telemetría del sistema.
       -------------------------------------------------------------------- */
    Route::controller(DashboardController::class)->group(function () {
        
        // Vista Principal: Despacho por Rol (Admin/Instr/Part) con Peaje de Perfil
        Route::get('/Dashboard', 'index')->name('dashboard');

        // API de Telemetría: Endpoint JSON para refrescar KPIs y salud de CPU/RAM cada 5s
        Route::get('/Dashboard/data', 'getDashboardData')->name('dashboard.data');

        // Matriz Académica: Carga masiva de cursos del año fiscal actual (Consumo de SP)
        Route::get('/OfertaAcademica', 'OfertaAcademica')->name('cursos.matriz');
    
        // █ AGREGA ESTA LÍNEA PARA EVITAR EL ERROR █
        // Por ahora la mandamos a una función que crearemos en el controlador
        Route::get('/Inscripcion/{id}', 'solicitarInscripcion')->name('cursos.inscripcion');

        // █ RUTA PARA EL PROCESO DE INSCRIPCIÓN █
        // Esta es la que falta para que el Modal funcione
        Route::post('/Inscripcion/Confirmar', 'confirmarInscripcion')
            ->name('cursos.inscripcion.confirmar');

    });

    /* --------------------------------------------------------------------
       B. MÓDULO DE IDENTIDAD (IMC - IDENTITY MASTER CONTROL)
       ────────────────────────────────────────────────────────────────────
       Transacciones atómicas sobre el expediente digital propio.
       Protección IDOR: No reciben ID por URL; consumen estrictamente Auth::id().
       -------------------------------------------------------------------- */
    Route::controller(UsuarioController::class)->group(function () {
        
        /* | █ PROTOCOLO DE IDENTIDAD PROPIA (IMC - IDENTITY MASTER CONTROL)
         | ─────────────────────────────────────────────────────────────────────────────
         | Este conjunto de rutas gobierna el ciclo de vida del expediente del usuario.
         | Implementa el Standard Platinum Forensic mediante la separación de vectores:
         | 0. HUB DE CUENTA: Interfaz intermedia de navegación.
         | 1. VECTORES BIOGRÁFICOS: Gestionados por el motor dual UpdateMiPerfil.
         | 2. VECTORES DE ACCESO: Protegidos en el búnker de UpdateCredenciales.
         | 3. PROTECCIÓN IDOR: No se exponen IDs en URL; se utiliza el contexto de sesión.
         */

        // █ 0. HUB DE LA CUENTA (Vista Intermedia / Tablero de Control)
        // Punto de aterrizaje principal cuando el usuario hace clic en "Mi Perfil".
        Route::get('/MiPerfil', function () {
            return view('panel.participant.MiPerfil.HubMiPerfil');
        })->name('perfil.hub');

        // █ 1. VECTORES BIOGRÁFICOS (Expediente e Identidad)
        // A. Consulta de Expediente (Modo Vitrina / Read-only)
        Route::get('/MiPerfil/Consultar', 'ShowMiPerfil')->name('perfil.show');

        // B. Preparación de Entorno (Motor GET - Onboarding / Edición)
        // Ambas rutas comparten el mismo cerebro lógico para entregar el formulario PascalCase.
        // La ruta 'completar' es el peaje de activación; 'edit' es la puerta de mantenimiento.
        Route::get('/CompletarMiPerfil', 'UpdateMiPerfil')->name('perfil.completar');
        Route::get('/MiPerfil/Editar', 'UpdateMiPerfil')->name('perfil.edit');

        // C. Motor de Persistencia Unificado (POST/PUT)
        // Atiende la activación inicial (POST) y las actualizaciones biográficas posteriores (PUT).
        // Centraliza la validación de los 16 parámetros y el Garbage Collector multimedia.
        Route::match(['post', 'put'], '/MiPerfil/Guardar', 'UpdateMiPerfil')->name('perfil.save');

        // D. Gestión de Seguridad (Búnker de Credenciales)
        // Aísla el cambio de Email y Password de los datos biográficos para reducir el riesgo.
        // Requiere que el controlador valide la autoridad mediante la contraseña física actual.
        Route::get('/MiPerfil/Seguridad', function() { return view('panel.participant.MiPerfil.Seguridad'); })->name('perfil.seguridad');
        Route::put('/MiPerfil/Seguridad/Update', 'UpdateCredenciales')->name('perfil.updateCredenciales');
        /**
         * █ GESTIÓN DOCENTE PROPIA
         * Consulta atómica de cursos impartidos por el usuario actual.
         * Roles permitidos como instructores: 1 (Admin), 2 (Coordinador), 3 (Instructor).
         */
        Route::get('/CursosImpartidos', 'CursosImpartidos')->name('instructor.cursos');
        
        Route::post('/Evaluacion/AbrirExpediente', 'vistaEvaluacion')->name('instructor.evaluacion.abrir');
        Route::post('/Evaluacion/Guardar', 'guardarEvaluacion')->name('instructor.evaluacion.guardar');

        // Descarga de Documentos (Constancias y DC-3)
        /*Route::get('/MiKardex/Descargar/{idCursoDetalle}', [UsuarioController::class, 'descargarConstancia'])
        ->name('perfil.descargar_constancia');*/
    });


    /* --------------------------------------------------------------------
       C. GESTIÓN ADMINISTRATIVA DE CAPITAL HUMANO
       ────────────────────────────────────────────────────────────────────
       Mapeo RESTful para el control total del directorio de usuarios.
       Exclusivo para el ROL ADMINISTRADOR (1).
       -------------------------------------------------------------------- */
    /* --------------------------------------------------------------------
       C. GESTIÓN ADMINISTRATIVA DE CAPITAL HUMANO
       ──────────────────────────────────────────────────────────────────── */

    // █ 1. CEREBRO DE HIDRATACIÓN DUAL (POST)
    // Vista de Consulta (Solo Lectura): /Usuarios/Expediente
    Route::post('/Usuarios/Expediente', [UsuarioController::class, 'show'])
        ->name('Usuarios.show');

    // Vista de Edición (Con controles): /Usuarios/Actualizar/Expediente
    // █ CAMBIO CLAVE: Nueva ruta para la URL extendida
    Route::post('/Usuarios/Actualizar/Expediente', [UsuarioController::class, 'show'])
        ->name('Usuarios.edit_view');

    // █ 2. MOTOR DE PERSISTENCIA ADMINISTRATIVA (PUT)
    // URL de Destino al guardar: /Usuarios/Actualizacion/{id}
    Route::put('/Usuarios/Actualizacion/{id}', [UsuarioController::class, 'update'])
        ->name('Usuarios.update');

    // █ 3. CONTROL DE CICLO DE VIDA (PATCH)
    Route::patch('/Usuarios/{id}/estatus', [UsuarioController::class, 'cambiarEstatus'])
        ->name('Usuarios.Estatus');

    // █ 4. RED DE SEGURIDAD (REBOTE ANTI-ENUMERACIÓN)
    // Bloqueamos el acceso GET manual a las URLs de expediente
    Route::get('/Usuarios/Expediente', function() { return redirect()->route('Usuarios.index'); });
    Route::get('/Usuarios/Actualizar/Expediente', function() { return redirect()->route('Usuarios.index'); });

    // █ 5. RESOURCE RESTANTE (CRUD BASE)
    Route::resource('Usuarios', UsuarioController::class)
        ->except(['create', 'show', 'edit', 'update']) 
        ->names([
            'index'   => 'Usuarios.index',
            'store'   => 'Usuarios.store',
            'destroy' => 'Usuarios.destroy',
        ]);
    
    Route::get('/Usuarios/Create', [UsuarioController::class, 'create'])->name('Usuarios.create');
    
    /* --------------------------------------------------------------------
       D. CENTRO DE COMUNICACIONES Y ARCHIVO
       ──────────────────────────────────────────────────────────────────── */
    
    // Mi Kárdex: Consulta de historial académico y descargas DC-3
    // █ AHORA (Solución Platinum): Apuntamos al archivo real que creaste
    /*Route::get('/MiKardex', function() { 
        return view('components.MiKardex'); 
    })->name('perfil.kardex');*/
    
    Route::get('/MiKardex', [UsuarioController::class, 'MiKardex'])
    ->name('perfil.kardex');

    // Notificaciones: Bitácora de eventos y logs del sistema
    Route::get('/CentrodeNotificaciones', function() { return view('notificaciones.index'); })
        ->name('notificaciones.index');

    // Mensajes: Centro de soporte y tickets técnicos
    Route::get('/CentrodeMensajes', function() { return view('mensajes.index'); })
        ->name('mensajes.index');

    // Ruta de descarga protegida
    /*Route::get('/Descargar-Constancia/{id}', [UsuarioController::class, 'descargarConstancia'])
        ->name('perfil.descargar_constancia');*/

    /* --------------------------------------------------------------------
       E. API INTERNA DE CATÁLOGOS (ADSCRIPCIÓN REACTIVA)
       ────────────────────────────────────────────────────────────────────
       Rutas de servicio para la hidratación de cascadas en formularios Smart.
       Consumidas por 'Picade.js' vía Fetch API.
       -------------------------------------------------------------------- */
    Route::prefix('api/catalogos')->group(function () {
        
        // Cascadas Geográficas (País -> Estado -> Municipio)
        Route::get('/estados/{idPais}', [CatalogoController::class, 'estadosPorPais']);
        Route::get('/municipios/{idEstado}', [CatalogoController::class, 'municipiosPorEstado']);
        
        // Cascadas Organizacionales PEMEX (Dirección -> Sub -> Gerencia)
        Route::get('/subdirecciones/{idDireccion}', [CatalogoController::class, 'subdireccionesPorDireccion']);
        Route::get('/gerencias/{idSubdireccion}', [CatalogoController::class, 'gerenciasPorSubdireccion']);
    });

    
    /* --------------------------------------------------------------------
       F. MÓDULO DE GESTIÓN OPERATIVA (CAPACITACIONES)
       ────────────────────────────────────────────────────────────────────
       Mapeo de rutas con estética PascalCase y protección Anti-IDOR.
       Exclusivo para Roles Administrativos (Coordinador y Admin).
       -------------------------------------------------------------------- */
    /*
    Route::controller(\App\Http\Controllers\CapacitacionesController::class)->group(function () {
        
        // █ 1. DASHBOARD COMPARATIVO GLOBAL (Nivel 1)
        Route::get('/Capacitaciones', 'index')
            ->name('capacitaciones.index');

        // █ 2. RESUMEN ANUAL ESPECÍFICO (Nivel 2)
        // Ejemplo URL: /Capacitaciones/ResumenAnual/2026
        Route::get('/Capacitaciones/ResumenAnual/{anio}', 'dashboardAnual')
            ->name('capacitaciones.anio');

        // █ 3. FORMULARIO DE CREACIÓN
        Route::get('/Capacitaciones/RegistarCapacitacion', 'create')
            ->name('capacitaciones.create');

        // █ 4. MOTOR DE ALTA (Destino del formulario Create)
        Route::post('/Capacitaciones/GuardarCapacitacion', 'store')
            ->name('capacitaciones.store');

        // █ 5. CEREBRO DE HIDRATACIÓN DUAL (POST - PROTECCIÓN ANTI-IDOR)
        // A diferencia de un recurso REST normal, aquí NO enviamos el ID en la URL.
        // Lo mandamos por POST en un formulario oculto.
        
        // Vista de Consulta (Solo Lectura)
        Route::post('/Capacitaciones/ConsultarCapacitacion', 'show')
            ->name('capacitaciones.show');

        // Vista de Edición (Con controles)
        Route::post('/Capacitaciones/EditarCapacitacion', 'edit')
            ->name('capacitaciones.edit_view');

        // █ 6. MOTORES DE PERSISTENCIA Y DESTRUCCIÓN
        // URL de Destino al guardar cambios (Update)
        Route::put('/Capacitaciones/Actualizar/{token_id}', 'update')
            ->name('capacitaciones.update');

        // Motor de Eliminación Física (Hard Delete)
        Route::delete('/Capacitaciones/Eliminar/{token_id}', 'destroy')
            ->name('capacitaciones.destroy');

        // █ 7. CONTROL DE CICLO DE VIDA (Archivar / Restaurar)
        Route::patch('/Capacitaciones/{token_id}/Estatus', 'toggleStatus')
            ->name('capacitaciones.estatus');
            
        // █ 8. RED DE SEGURIDAD (REBOTE ANTI-ENUMERACIÓN)
        // Bloqueamos el acceso GET manual a las URLs protegidas
        Route::get('/Capacitaciones/ConsultarCapacitacion', function() { return redirect()->route('capacitaciones.index'); });
        Route::get('/Capacitaciones/EditarCapacitacion', function() { return redirect()->route('capacitaciones.index'); });
    });*/
});
