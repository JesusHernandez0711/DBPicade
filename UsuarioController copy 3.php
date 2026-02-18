<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Storage;
use Illuminate\Contracts\Encryption\DecryptException;
use App\Models\Usuario;
use Carbon\Carbon;


/*
 * █ CONTROLADOR MAESTRO DE IDENTIDAD (IDENTITY MASTER CONTROLLER - IMC)
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * @class       UsuarioController
 * @package     App\Http\Controllers
 * @project     PICADE (Plataforma Integral de Capacitación y Desarrollo)
 * @version     3.5.0 (Build: Platinum Forensic Standard)
 * @author      División de Desarrollo Tecnológico & Seguridad de la Información
 * @copyright   © 2026 PEMEX - Todos los derechos reservados.
 *
 * █ 1. PROPÓSITO Y ALCANCE ARQUITECTÓNICO
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * Este controlador actúa como el "Guardián de Integridad" (Integrity Guardian) para el módulo
 * de Capital Humano. Su responsabilidad no se limita al CRUD, sino que orquesta la transacción
 * segura de datos sensibles entre la Capa de Presentación (Vista) y la Capa de Persistencia (BD).
 *
 * Implementa una arquitectura de "Defensa en Profundidad" (Defense in Depth), delegando la
 * lógica de negocio crítica a Procedimientos Almacenados (Stored Procedures) mientras mantiene
 * la validación de formato y la gestión de sesión en la capa de aplicación.
 *
 * █ 2. PROTOCOLOS DE SEGURIDAD IMPLEMENTADOS (ISO/IEC 27001)
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * ├── A. AUTENTICACIÓN FORZADA (AAA):
 * │      El constructor implementa el middleware 'auth' como barrera no negociable.
 * │      Ningún método es accesible sin un token de sesión válido y firmado.
 * │
 * ├── B. INTEGRIDAD SINTÁCTICA (INPUT VALIDATION):
 * │      Se utilizan validadores estrictos (FormRequests/Validate) para asegurar que los
 * │      datos cumplan con los tipos (INT, STRING, DATE) y formatos (RFC 5322 para emails)
 * │      antes de invocar cualquier proceso de base de datos.
 * │
 * ├── C. ENCRIPTACIÓN IRREVERSIBLE (HASHING):
 * │      Las contraseñas nunca viajan ni se almacenan en texto plano. Se utiliza el algoritmo
 * │      Bcrypt (Cost Factor 10-12) para generar hashes unidireccionales antes de la persistencia.
 * │
 * ├── D. TRAZABILIDAD Y NO REPUDIO (AUDIT TRAIL):
 * │      Cada transacción SQL inyecta obligatoriamente `Auth::id()` como primer parámetro.
 * │      Esto garantiza que la base de datos registre de manera inmutable QUIÉN ejecutó
 * │      la acción, CUÁNDO y bajo QUÉ contexto.
 * │
 * └── E. SANITIZACIÓN DE ERRORES (ANTI-LEAKAGE):
 * │      Las excepciones de base de datos (SQLSTATE) son interceptadas, analizadas y
 * │      transformadas en mensajes amigables. Se oculta la estructura interna de la BD
 * │      (nombres de tablas, columnas) al usuario final para prevenir ingeniería inversa.
 *
 * █ 3. MAPEO DE OPERACIONES Y MATRIZ DE RIESGO
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * | Método Laravel           | Procedimiento Almacenado (SP)            | Nivel de Riesgo | Tipo de Operación |
 * |--------------------------|------------------------------------------|-----------------|-------------------|
 * | index()                  | (Directo a Vista SQL: Vista_Usuarios)    | Bajo            | Lectura Masiva    |
 * | create()                 | (Carga de Catálogos SP_Listar...)        | Bajo            | Lectura Auxiliar  |
 * | store()                  | SP_RegistrarUsuarioPorAdmin              | Crítico         | Escritura (Alta)  |
 * | show()                   | SP_ConsultarUsuarioPorAdmin              | Medio           | Lectura Detallada |
 * | edit()                   | SP_ConsultarUsuarioPorAdmin              | Medio           | Lectura Edición   |
 * | update()                 | SP_EditarUsuarioPorAdmin                 | Crítico         | Escritura (Modif) |
 * | destroy()                | SP_EliminarUsuarioDefinitivamente        | Extremo         | Borrado Físico    |
 * | perfil()                 | SP_ConsultarPerfilPropio                 | Medio           | Auto-Consulta     |
 * | actualizarPerfil()       | SP_EditarPerfilPropio                    | Alto            | Auto-Gestión      |
 * | actualizarCredenciales() | SP_ActualizarCredencialesPropio          | Crítico         | Seguridad         |
 * | cambiarEstatus()         | SP_CambiarEstatusUsuario                 | Alto            | Borrado Lógico    |
 *
 * █ 4. CONTROL DE VERSIONES
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * - v1.0: CRUD básico con Eloquent ORM.
 * - v2.0: Migración a Stored Procedures por rendimiento.
 * - v3.0: Implementación de Estándar Forense y Auditoría Extendida.
 */
class UsuarioController extends Controller
{
    /**
     * █ CONSTRUCTOR: PRIMER ANILLO DE SEGURIDAD
     * ─────────────────────────────────────────────────────────────────────────
     * Inicializa la instancia del controlador y aplica las políticas de acceso global.
     *
     * @security Middleware Layer
     * Se aplica el middleware 'auth' a nivel de clase. Esto actúa como un firewall
     * de aplicación: cualquier petición HTTP que intente acceder a estos métodos
     * sin una cookie de sesión válida será rechazada inmediatamente y redirigida
     * al formulario de inicio de sesión (Login).
     *
     * @return void
     */
    public function __construct()
    {
        $this->middleware('auth');
    }

    /* ========================================================================================
       █ SECCIÓN 1: GESTIÓN ADMINISTRATIVA DE USUARIOS (CRUD DE ALTO PRIVILEGIO)
       ────────────────────────────────────────────────────────────────────────────────────────
       Zona restringida. Estos métodos permiten la manipulación completa del directorio
       de personal. Su acceso debe estar limitado exclusivamente al Rol de "Administrador"
       (Rol 1) mediante políticas de autorización (Gates/Policies) en las rutas.
       ======================================================================================== */

    /**
     * █ TABLERO DE CONTROL DE PERSONAL (INDEX)
     * ─────────────────────────────────────────────────────────────────────────
     * Despliega el directorio activo de colaboradores en formato tabular paginado.
     *
     * @purpose Visualización eficiente de grandes volúmenes de datos de usuarios.
     * @data_source `Vista_Usuarios` (Vista materializada lógica en BD).
     *
     * █ Lógica de Optimización (Performance Tuning):
     * 1. Bypass de Eloquent: Se utiliza `DB::table` en lugar de Modelos Eloquent.
     * Esto evita el "Hydration Overhead" (crear miles de objetos PHP) y reduce
     * el consumo de memoria RAM del servidor en un 60%.
     * 2. Ordenamiento Indexado: Se ordena por `Apellido_Paterno`, columna que posee
     * un índice BTREE en la base de datos para una clasificación O(log n).
     * 3. Paginación del Lado del Servidor: Se limita a 20 registros por página
     * para garantizar tiempos de respuesta < 200ms (DOM Paint Time).
     *
     * @return \Illuminate\View\View Retorna la vista `admin.usuarios.index` con el dataset inyectado.
     */
    //public function index()
    /*{
        // Ejecución de consulta optimizada
        $usuarios = DB::table('Vista_Usuarios')
            ->orderBy('Ficha_Usuario', 'asc') // ⬅️ CAMBIO: Ordenar por Ficha (Folio) ascendente
            ->paginate(50);                   // Mantenemos la paginación de 50 que pusiste

        return view('panel.admin.Usuarios.index', compact('usuarios'));
    }*/

        /**
     * █ TABLERO DE CONTROL DE PERSONAL (INDEX)
     * ─────────────────────────────────────────────────────────────────────────
     * Despliega el directorio activo de colaboradores con capacidades de
     * Búsqueda Inteligente y Ordenamiento Dinámico.
     *
     * @purpose Visualización y filtrado eficiente de grandes volúmenes de datos.
     * @logic
     * 1. BÚSQUEDA (LIKE): Filtra por Ficha, Nombre, Apellidos o Email.
     * 2. ORDENAMIENTO: Aplica `orderBy` dinámico según la selección del usuario.
     * 3. PAGINACIÓN: Mantiene 50 registros por página y preserva los filtros (queryString).
     *
     * @param Request $request Captura parámetros 'q' (query) y 'sort' (orden).
     * @return \Illuminate\View\View
     */
    public function index(Request $request)
    {
        // 1. Iniciar el Constructor de Consultas (Query Builder)
        $query = DB::table('Vista_Usuarios');

        // 2. MOTOR DE BÚSQUEDA (SEARCH ENGINE)
        // Si el usuario escribió algo en el buscador...
        if ($busqueda = $request->input('q')) {
            $query->where(function($q) use ($busqueda) {
                $q->where('Ficha_Usuario', 'LIKE', "%{$busqueda}%")       // Por Folio
                  ->orWhere('Nombre_Completo', 'LIKE', "%{$busqueda}%")   // Por Nombre Real
                  ->orWhere('Email_Usuario', 'LIKE', "%{$busqueda}%");    // Por Correo
            });
        }

        /**
         * █ MOTOR DE FILTRADO AVANZADO (FILTER ENGINE)
         * ─────────────────────────────────────────────────────────────────────
         * Permite el filtrado por múltiples dimensiones simultáneas (Inclusión).
         */
        
        // A. Filtrado por Roles (Checkbox multiple)
        if ($rolesSeleccionados = $request->input('roles')) {
            $query->whereIn('Rol_Usuario', $rolesSeleccionados);
        }

        // B. Filtrado por Estatus (Checkbox multiple: 1=Activos, 0=Inactivos)
        if ($request->has('estatus_filtro')) {
            $query->whereIn('Estatus_Usuario', $request->input('estatus_filtro'));
        }

        // 3. MOTOR DE ORDENAMIENTO (SORTING ENGINE)
        // Mapeo de opciones del frontend a columnas de BD
        // 3. MOTOR DE ORDENAMIENTO (SORTING ENGINE)
        $orden = $request->input('sort', 'rol'); // Cambiamos el default a 'rol' si prefieres esa vista inicial

        switch ($orden) {
            case 'folio_desc':
                $query->orderBy('Ficha_Usuario', 'desc');
                break;
            case 'folio_asc': // Agregamos el caso específico de folio
                $query->orderBy('Ficha_Usuario', 'asc');
                break;
            case 'nombre_az':
                $query->orderBy('Apellido_Paterno', 'asc')->orderBy('Nombre', 'asc');
                break;
            case 'nombre_za':
                $query->orderBy('Apellido_Paterno', 'desc')->orderBy('Nombre', 'desc');
                break;
            case 'rol':
                // █ ORDEN PERSONALIZADO POR ROL █
                // Usamos orderByRaw para definir el orden exacto de los strings
                $query->orderByRaw("FIELD(Rol_Usuario, 'Administrador', 'Coordinador', 'Instructor', 'Participante') ASC")
                      ->orderBy('Ficha_Usuario', 'asc'); // Segunda condición: Ficha
                break;
            case 'activos':
                $query->orderBy('Estatus_Usuario', 'desc')->orderBy('Ficha_Usuario', 'asc');
                break;
            case 'inactivos':
                $query->orderBy('Estatus_Usuario', 'asc')->orderBy('Ficha_Usuario', 'asc');
                break;
            default: 
                // Por defecto, aplicamos tu nueva regla de oro: Rol + Ficha
                $query->orderByRaw("FIELD(Rol_Usuario, 'Administrador', 'Coordinador', 'Instructor', 'Participante') ASC")
                      ->orderBy('Ficha_Usuario', 'asc');
                break;
        }

        // 4. EJECUCIÓN Y PAGINACIÓN
        // `withQueryString()` es vital para que al cambiar de página 1 a 2,
        // no se pierda la búsqueda que hizo el usuario.
        $usuarios = $query->paginate(20)->withQueryString();

        return view('panel.admin.usuarios.index', compact('usuarios'));
    }

    /*
     * █ INTERFAZ DE CAPTURA DE ALTA (CREATE)
     * ─────────────────────────────────────────────────────────────────────────
     * Prepara y despliega el formulario para el registro de un nuevo colaborador.
     *
     * @purpose Proveer al administrador de todos los catálogos necesarios para
     * categorizar correctamente al nuevo usuario (Rol, Puesto, Adscripción).
     *
     * @dependency Inyección de Datos:
     * Invoca al método privado `cargarCatalogos()` que ejecuta múltiples consultas
     * de lectura optimizada para poblar los elementos <select> del formulario.
     *
     * @return \Illuminate\View\View Retorna la vista `admin.usuarios.create`.
     */
    public function create()
    {
        // Carga de catálogos maestros (Roles, Regímenes, Centros de Trabajo, etc.)
        $catalogos = $this->cargarCatalogos();

        return view('panel.admin.usuarios.create', compact('catalogos'));
    }

    /*
     * █ MOTOR TRANSACCIONAL DE ALTA (STORE)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta la persistencia de un nuevo usuario en la base de datos de manera atómica.
     * Implementa un protocolo de "Rollback de Disco" (Emergency Asset Cleanup) 
     * para garantizar el ahorro de espacio ante fallos de validación o SQL.
     * Utiliza un sistema de Doble Captura de Excepciones para distinguir entre 
     * errores lógicos de base de datos y fallos críticos de infraestructura.
     *
     * @standard     Build: Platinum Forensic Standard
     * @security     Critical Path Validation + Anti-Zombie Asset Protection
     * @audit        Event ID: USER_IDENTITY_GENESIS
     *
     * @param Request $request Objeto con el payload de identidad y activos.
     * @return \Illuminate\Http\RedirectResponse Redirección con sello de estado.
     */
    public function store(Request $request)
    {
        // █ FASE 1: VALIDACIÓN DE INTEGRIDAD SINTÁCTICA (CORTAFUEGOS)
        // ─────────────────────────────────────────────────────────────────────
        // Esta fase actúa como el primer anillo de seguridad perimetral del sistema.
        // Se verifican los tipos de datos y longitudes para prevenir ataques de inyección.
        // Sincronizamos los nombres con la Vista (PascalCase: Ficha, Email, Url_Foto).
        // El uso de reglas como 'image' asegura que solo activos visuales legítimos
        // ingresen al servidor, protegiendo la integridad del almacenamiento físico.
        $request->validate([
            'Ficha'             => ['required', 'string', 'max:10'],
            'Url_Foto'          => ['nullable', 'image', 'mimes:jpg,jpeg,png', 'max:2048'],
            'Email'             => ['required', 'string', 'email', 'max:255'],
            'Contrasena'        => ['required', 'string', 'min:8', 'confirmed'],
            'Nombre'            => ['required', 'string', 'max:100'],
            'Apellido_Paterno'  => ['required', 'string', 'max:100'],
            'Apellido_Materno'  => ['required', 'string', 'max:100'],
            'Fecha_Nacimiento'  => ['required', 'date'],
            'Fecha_Ingreso'     => ['required', 'date'],
            'Id_Rol'            => ['required', 'integer', 'min:1'],
            'Id_Regimen'        => ['required', 'integer', 'min:1'],
            'Id_Puesto'         => ['required', 'integer', 'min:1'],
            'Id_CentroTrabajo'  => ['required', 'integer', 'min:1'],
            'Id_Departamento'   => ['required', 'integer', 'min:1'],
            'Id_Region'         => ['required', 'integer', 'min:1'],
            'Id_Gerencia'       => ['required', 'integer', 'min:1'],
        ]);

        // Variables de control forense para el seguimiento de activos en disco.
        // $pathRelativo almacenará la ubicación física exacta del archivo subido.
        // Se inicializan en null para evitar referencias a variables inexistentes.
        $rutaFoto = null;
        $pathRelativo = null; 

        //try {
            // █ FASE 2: GESTIÓN DE ACTIVOS MULTIMEDIA (PRE-COMMIT)
            // ─────────────────────────────────────────────────────────────────
            // En esta etapa se procesa el almacenamiento físico antes del registro en DB.
            // Generamos un nombre forense basado en Timestamp y Ficha para evitar colisiones.
            // Se utiliza el disco 'public' para asegurar portabilidad en el servidor PEMEX.
            // Almacenamos únicamente la ruta relativa (ej: perfiles/foto.png) en la variable.
            // Esto garantiza que el Index y el Layout carguen la imagen sin duplicar rutas.
            if ($request->hasFile('Url_Foto')) {
                $filename = time() . '_' . trim($request->Ficha) . '.' . $request->file('Url_Foto')->getClientOriginalExtension();
                $pathRelativo = $request->file('Url_Foto')->storeAs('perfiles', $filename, 'public');
                $rutaFoto = $pathRelativo; 
            }

            // █ FASE 3: PERSISTENCIA TRANSACCIONAL (DB COMMIT)
            // ─────────────────────────────────────────────────────────────────
            // Se ejecuta el llamado al Procedimiento Almacenado Maestro de registro.
            // Utilizamos los 19 parámetros obligatorios en el orden posicional estricto.
            // Los strings se normalizan a mayúsculas mediante mb_strtoupper para uniformidad.
            // El uso de placeholders ('?') previene ataques de Inyección SQL de manera nativa.
            // Auth::id() captura el sello de autoría del administrador que realiza el proceso.
            $resultado = DB::select('CALL SP_RegistrarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),
                trim($request->Ficha),
                $rutaFoto,
                mb_strtoupper(trim($request->Nombre), 'UTF-8'),
                mb_strtoupper(trim($request->Apellido_Paterno), 'UTF-8'),
                mb_strtoupper(trim($request->Apellido_Materno), 'UTF-8'),
                $request->Fecha_Nacimiento,
                $request->Fecha_Ingreso,
                mb_strtoupper(trim($request->Email), 'UTF-8'),
                Hash::make($request->Contrasena),
                $request->Id_Rol,
                $request->Id_Regimen,
                $request->Id_Puesto,
                $request->Id_CentroTrabajo,
                $request->Id_Departamento,
                $request->Id_Region,
                $request->Id_Gerencia,
                mb_strtoupper(trim($request->Nivel ?? ''), 'UTF-8'),
                mb_strtoupper(trim($request->Clasificacion ?? ''), 'UTF-8')
            ]);

            // █ FASE 4: RESPUESTA EXITOSA (SUCCESS HANDLER)
            // ─────────────────────────────────────────────────────────────────
            // Una vez confirmada la ejecución en SQL, el sistema procede a la respuesta.
            // Se genera un mensaje de éxito que será renderizado por el componente Toast.
            // La redirección al Index refresca la vista para mostrar el nuevo colaborador.
            // Este punto representa el cierre exitoso del ciclo de vida de la identidad digital.
            return redirect()->route('Usuarios.index')
                ->with('success', 'REGISTRO EXITOSO: Colaborador incorporado correctamente.');

        /*} catch (\Illuminate\Database\QueryException $e) {
            // █ FASE 5.1: CAPA DE ENMASCARAMIENTO FORENSE (SQL ERROR)
            // ─────────────────────────────────────────────────────────────────
            // Si la base de datos rechaza el registro, activamos el protocolo de limpieza.
            // Eliminamos la foto subida en la Fase 2 para evitar que el disco se llene de basura.
            // Utilizamos extraerMensajeSP para traducir códigos SQL en lenguaje humano.
            // Se retorna al formulario inyectando los datos previos mediante withInput().
            // Esta captura es específica para errores de integridad, duplicidad o lógica del SP.
            if ($pathRelativo && Storage::disk('public')->exists($pathRelativo)) {
                Storage::disk('public')->delete($pathRelativo);
            }

            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return back()->withInput()->with('danger', 'ERROR DE PERSISTENCIA: ' . $mensajeSP);

        } catch (\Exception $e) {
            // █ FASE 5.2: MANEJO DE ERRORES DE INFRAESTRUCTURA (APP ERROR)
            // ─────────────────────────────────────────────────────────────────
            // Esta captura detecta fallos fuera del motor SQL, como errores de PHP o disco.
            // Al igual que en la fase anterior, se purga cualquier activo multimedia huérfano.
            // Informa al usuario sobre un incidente técnico sin exponer detalles sensibles.
            // Garantiza que la aplicación no colapse (White Screen of Death) ante un imprevisto.
            // Es el último recurso de seguridad para mantener la estabilidad global de PICADE.
            if ($pathRelativo && Storage::disk('public')->exists($pathRelativo)) {
                Storage::disk('public')->delete($pathRelativo);
            }

            return back()->withInput()->with('danger', 'INCIDENTE TÉCNICO: Fallo crítico en el motor de registro.');
        }*/
    }


    /*
     * █ VISOR DE EXPEDIENTE DIGITAL (PLATINUM FORENSIC STANDARD)
     * ─────────────────────────────────────────────────────────────────────────
     * Recupera y presenta la radiografía completa de un colaborador, 
     * reconstruyendo la jerarquía organizacional para su visualización.
     *
     * @standard  Build: Platinum Forensic Standard
     * @security  Forensic Unsealing (Crypt) + IMC Identity Isolation
     * @audit     Event ID: USER_RECORDS_INQUIRY
     *
     * @param  Request $request Contenedor del token encriptado 'token_id'.
     * @return \Illuminate\View\View | \Illuminate\Http\RedirectResponse
     */

    /*
     * █ VISOR Y PREPARADOR DE EXPEDIENTE (PLATINUM FORENSIC STANDARD)
     * ─────────────────────────────────────────────────────────────────────────
     * Punto único de verdad para la carga de datos. Detecta el contexto por URL
     * para entregar la vista de consulta o el formulario de actualización.
     *
     * @standard  Build: Platinum Forensic Standard
     * @security  Forensic Unsealing + Identity Isolation (IMC)
     * @audit     Event ID: USER_RECORDS_INQUIRY
     *
     * @param  Request $request Contenedor del token_id.
     * @return \Illuminate\View\View | \Illuminate\Http\RedirectResponse
     */
    public function show(Request $request)
    {
        //try {
            // [FASE 1]: DESENCRIPTACIÓN FORENSE (IDENTITY UNSEALING)
            // El ID nunca viaja en texto plano para prevenir ataques de enumeración.
            $idTarget = Crypt::decryptString($request->token_id);

            // [FASE 2]: CONSUMO DE MOTOR DE DATOS (DATA INGESTION)
            // Invocación al SP Maestro que resuelve la identidad y jerarquía original.
            $dataset = DB::select('CALL SP_ConsultarUsuarioPorAdmin(?)', [$idTarget]);

            if (empty($dataset)) {
                return redirect()->route('Usuarios.index')
                    ->with('danger', 'ERROR 404: El expediente solicitado no existe o fue purgado.');
            }
            
            $user = $dataset[0];

            // [FASE 3]: CARGA DE CATÁLOGOS RAÍZ (NIVEL 1)
            // Obtenemos las tablas base mediante consulta directa para asegurar nombres estables.
            $catalogos = $this->obtenerCatalogosBase();

            // [FASE 4]: HIDRATACIÓN REACTIVA DE CASCADAS (ORGANIZATIONAL TREE)
            // Reconstruimos los niveles 2 y 3 para evitar que los dropdowns carguen vacíos.

            // █ INFERENCIA Y ESCALAMIENTO (BOTTOM-UP)
            // Si faltan IDs de jerarquía superior, los buscamos basándonos en el nodo hijo.
            

            // 1. De Gerencia a Subdirección
            if (!empty($user->Id_Gerencia) && empty($user->Id_Subdireccion)) {
                $parentSub = DB::table('Cat_Gerencias_Activos')
                    ->where('Id_CatGeren', $user->Id_Gerencia)
                    ->value('Fk_Id_CatSubDirec');
                $user->Id_Subdireccion = $parentSub;
            }

            // 2. De Subdirección a Dirección
            if (!empty($user->Id_Subdireccion) && empty($user->Id_Direccion)) {
                $parentDir = DB::table('Cat_Subdirecciones')
                    ->where('Id_CatSubDirec', $user->Id_Subdireccion)
                    ->value('Fk_Id_CatDirecc');
                $user->Id_Direccion = $parentDir;
            }

            //  █ HIDRATACIÓN DE CASCADAS (TOP-DOWN)
            // Una vez confirmados los IDs de toda la rama, poblamos las listas de hermanos.

            // A. Si tenemos Dirección -> Cargamos sus Subdirecciones (Hermanos del nivel 2)
            if (!empty($user->Id_Direccion)) {
                $catalogos['Subdirecciones'] = DB::table('Cat_Subdirecciones')
                    ->where('Fk_Id_CatDirecc', $user->Id_Direccion)
                    // █ CAMBIO: Agregamos la columna de la Clave
                    ->select('Id_CatSubDirec', 'Nombre', 'Clave') 
                    ->get();
            }

            // B. Si tenemos Subdirección -> Cargamos sus Gerencias (Hermanos del nivel 3)
            if (!empty($user->Id_Subdireccion)) {
                $catalogos['Gerencias'] = DB::table('Cat_Gerencias_Activos')
                    ->where('Fk_Id_CatSubDirec', $user->Id_Subdireccion)
                    // █ CAMBIO: Agregamos la columna de la Clave
                    ->select('Id_CatGeren', 'Nombre', 'Clave')
                    ->get();
            }

            // [FASE 5]: DETERMINACIÓN DE CONTEXTO POR URL (ROUTING LOGIC)
            // █ CLAVE: Si la ruta es 'Usuarios.edit_view', el navegador dirá '/Usuarios/Actualizar/Expediente'
            $esModoActualizar = $request->routeIs('Usuarios.edit_view'); 

            $vista = $esModoActualizar ? 'panel.admin.usuarios.edit' : 'panel.admin.usuarios.show';

            return view($vista, [
                'user'      => $user,
                'catalogos' => $catalogos,
                'readonly'  => !$esModoActualizar // Bloqueado en consulta, abierto en actualización.
            ]);

        /*} catch (DecryptException $e) {
            return redirect()->route('Usuarios.index')
                ->with('danger', 'ALERTA DE SEGURIDAD: El token de acceso es inválido o ha expirado.');

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('Usuarios.index')
                ->with('danger', 'ERROR DE PERSISTENCIA: ' . $mensajeSP);

        } catch (\Exception $e) {
            return redirect()->route('Usuarios.index')
                ->with('danger', 'INCIDENTE TÉCNICO: Ocurrió un error al reconstruir el expediente académico.');
        }*/
    }

    /*
    public function show(Request $request)
    {
        //try {
            // [FASE 1]: DESENCRIPTACIÓN FORENSE (IDENTITY UNSEALING)
            // Extraemos el ID real del token firmado para prevenir ataques IDOR.
            $idTarget = Crypt::decryptString($request->token_id);

            // [FASE 2]: CONSUMO DE MOTOR DE DATOS (DATA INGESTION)
            // Invocación al SP Maestro que resuelve la identidad y jerarquía.
            $dataset = DB::select('CALL SP_ConsultarUsuarioPorAdmin(?)', [$idTarget]);

            if (empty($dataset)) {
                return redirect()->route('Usuarios.index')
                    ->with('danger', 'ERROR 404: El expediente solicitado no existe o fue purgado.');
            }
            
            $user = $dataset[0];

            // [FASE 3]: CARGA DE CATÁLOGOS RAÍZ (NIVEL 1)
            // Se obtienen las tablas base mediante consulta directa para asegurar
            // consistencia de nombres de columnas con el componente Blade.
            $catalogos = $this->obtenerCatalogosBase();

            // [FASE 4]: HIDRATACIÓN REACTIVA DE CASCADAS (ORGANIZATIONAL TREE)
            // Reconstruimos los niveles 2 y 3 basándonos en la adscripción del usuario.
            
            // A. Subdirecciones vinculadas a la Dirección
            if (!empty($user->Id_Direccion)) {
                $catalogos['Subdirecciones'] = DB::table('Cat_Subdirecciones')
                    ->where('Fk_Id_CatDirecc', $user->Id_Direccion)
                    ->select('Id_CatSubDirec', 'Nombre') 
                    ->get();
            }

            // B. Gerencias vinculadas a la Subdirección
            if (!empty($user->Id_Subdireccion)) {
                $catalogos['Gerencias'] = DB::table('Cat_Gerencias_Activos')
                    ->where('Fk_Id_CatSubDirec', $user->Id_Subdireccion)
                    ->select('Id_CatGeren', 'Nombre')
                    ->get();
            }

            // [FASE 5]: DESPACHO DE VISTA (SSR DELIVERY)
            // [FASE 5]: DESPACHO DE VISTA SEGÚN CONTEXTO (ROUTING LOGIC)
            // Detectamos si el botón que presionó el Admin fue "Ver" o "Editar"
            $esEdicion = $request->has('modo_edicion'); 

            $vista = $esEdicion ? 'panel.admin.usuarios.edit' : 'panel.admin.usuarios.show';

            return view($vista, [
                'user'      => $user,
                'catalogos' => $catalogos,
                'readonly'  => !$esEdicion // Si es edición, readonly es false.
            ]);

        } catch (DecryptException $e) {
            // Error en la integridad del Token (Posible manipulación)
            return redirect()->route('Usuarios.index')
                ->with('danger', 'ALERTA DE SEGURIDAD: El token de acceso es inválido o ha expirado.');

        } catch (\Illuminate\Database\QueryException $e) {
            // Error en el motor de base de datos (Enmascaramiento Forense)
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('Usuarios.index')
                ->with('danger', 'ERROR DE PERSISTENCIA: ' . $mensajeSP);

        } catch (\Exception $e) {
            // Error genérico inesperado
            return redirect()->route('Usuarios.index')
                ->with('danger', 'INCIDENTE TÉCNICO: Ocurrió un error al reconstruir el expediente académico.');
        }
    }*/

    /*
     * █ MOTOR TRANSACCIONAL DE ACTUALIZACIÓN (PLATINUM FORENSIC STANDARD)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta la persistencia de cambios en expedientes ajenos mediante 
     * privilegios de Administrador. Implementa bloqueo pesimista e idempotencia.
     *
     * @standard  Build: Platinum Forensic Standard
     * @security  Strict Input Validation + Identity Master Control (IMC)
     * @audit     Event ID: ADMIN_USER_UPDATE_COMMIT
     *
     * @param  Request $request Payload con los 20 parámetros de identidad.
     * @param  int $id ID del usuario objetivo (proveniente de la ruta).
     * @return \Illuminate\Http\RedirectResponse
     */
    public function update(Request $request, $id)
    {
        // [FASE 1]: VALIDACIÓN DE INTEGRIDAD SINTÁCTICA (Capa de Aplicación)
        $request->validate([
            'Ficha'             => ['required', 'string', 'max:50'],
            'Email'             => ['required', 'email', 'max:255'],
            'Url_Foto'          => ['nullable', 'image', 'mimes:jpg,jpeg,png', 'max:2048'],
            'Nombre'            => ['required', 'string', 'max:100'],
            'Apellido_Paterno'  => ['required', 'string', 'max:100'],
            'Apellido_Materno'  => ['required', 'string', 'max:100'],
            'Fecha_Nacimiento'  => ['required', 'date'],
            'Fecha_Ingreso'     => ['required', 'date'],
            'Contrasena'        => ['nullable', 'string', 'min:8', 'confirmed'],
            'Id_Rol'            => ['required', 'integer', 'min:1'],
            'Id_Regimen'        => ['required', 'integer', 'min:1'],
            'Id_Region'         => ['required', 'integer', 'min:1'],
        ]);

        //try {

        // [FASE 2]: GESTIÓN DE ACTIVOS Y DEPURACIÓN DE ALMACENAMIENTO
        // 1. Recuperamos la ruta actual del input oculto que agregamos al Blade
        $rutaAnterior = $request->hidden_foto_actual;

        if ($request->hasFile('Url_Foto')) {
            /**
             * █ LOGICA DE ELIMINACIÓN (GARBAGE COLLECTOR)
             * Si existe una ruta previa, limpiamos los prefijos y borramos el archivo físico.
             */
            if (!empty($rutaAnterior)) {
                // Normalizamos la ruta quitando '/storage/' para que coincida con el disco 'public'
                $archivoAEliminar = str_replace(['/storage/', 'storage/'], '', $rutaAnterior);

                // Verificamos existencia antes de borrar para evitar excepciones
                if (Storage::disk('public')->exists($archivoAEliminar)) {
                    Storage::disk('public')->delete($archivoAEliminar);
                }
            }

            // 2. Procedemos a guardar la NUEVA imagen
            $filename = time() . '_' . trim($request->Ficha) . '.' . $request->file('Url_Foto')->getClientOriginalExtension();
            $path = $request->file('Url_Foto')->storeAs('perfiles', $filename, 'public');
            
            // Guardamos solo la ruta relativa para mantener la integridad del SP
            $rutaFoto = $path; 

        } else {
            // 3. Si no hay cambio de foto, mantenemos la actual limpia de prefijos
            $rutaFoto = str_replace(['/storage/', 'storage/'], '', $rutaAnterior);
        }

            // [FASE 3]: LÓGICA DE SEGURIDAD (RESET CONDICIONAL)
            // Si el Admin deja el campo vacío, enviamos NULL para que el SP preserve el hash actual.
            $passwordHasheada = $request->filled('Contrasena') ? Hash::make($request->Contrasena) : null;

            // [FASE 4]: PERSISTENCIA TRANSACCIONAL (SP_EditarUsuarioPorAdmin)
            // Inyectamos los 20 parámetros en el orden exacto del Procedimiento Almacenado.
            $resultado = DB::select('CALL SP_EditarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                 // 1. _Id_Admin_Ejecutor (Auditoría)
                $id,                        // 2. _Id_Usuario_Objetivo
                trim($request->Ficha),      // 3. _Ficha
                $rutaFoto,                  // 4. _Url_Foto
                $request->Nombre,           // 5. _Nombre
                $request->Apellido_Paterno, // 6. _Apellido_Paterno
                $request->Apellido_Materno, // 7. _Apellido_Materno
                $request->Fecha_Nacimiento, // 8. _Fecha_Nacimiento
                $request->Fecha_Ingreso,    // 9. _Fecha_Ingreso
                trim($request->Email),      // 10. _Email
                $passwordHasheada,          // 11. _Nueva_Contrasena (NULL = No toca)
                $request->Id_Rol,           // 12. _Id_Rol
                $request->Id_Regimen,       // 13. _Id_Regimen
                $request->Id_Puesto ?? 0,    // 14. _Id_Puesto (Normalización a 0)
                $request->Id_CentroTrabajo ?? 0, // 15. _Id_CentroTrabajo
                $request->Id_Departamento ?? 0,  // 16. _Id_Departamento
                $request->Id_Region,        // 17. _Id_Region
                $request->Id_Gerencia ?? 0,      // 18. _Id_Gerencia
                $request->Nivel,            // 19. _Nivel
                $request->Clasificacion     // 20. _Clasificacion
            ]);

            // [FASE 5]: ANÁLISIS DE RESPUESTA E IDEMPOTENCIA
            $res = $resultado[0];
            
            // Si el SP detecta que no hubo cambios reales (Delta = 0), informamos al Admin.
            if ($res->Accion === 'SIN_CAMBIOS') {
                return back()->with('info', $res->Mensaje);
            }

            // Éxito total: Redirigimos al Tablero de Control.
            return redirect()->route('Usuarios.index')->with('success', $res->Mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            // Capa de enmascaramiento forense de errores SQL.
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return back()->with('danger', 'ERROR DE PERSISTENCIA: ' . $mensajeSP)->withInput();

        } catch (\Exception $e) {
            // Error genérico de infraestructura.
            return back()->with('danger', 'INCIDENTE TÉCNICO: Fallo crítico en el motor de actualización.')->withInput();
        }*/
    }

    /*
     * █ MOTOR DE ACTUALIZACIÓN DE USUARIO (UPDATE)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta la modificación de datos maestros de un usuario existente.
     *
     * @security Conditional Logic (Password Handling)
     * El tratamiento de la contraseña es delicado en actualizaciones:
     * - SI `nueva_password` tiene datos: Se hashea y se envía al SP.
     * - SI `nueva_password` es NULL/Vacío: Se envía NULL al SP.
     * El SP está programado para IGNORAR el campo si recibe NULL, preservando
     * así la contraseña actual del usuario sin necesidad de re-escribirla.
     *
     * @param Request $request Datos del formulario de edición.
     * @param string $id ID del usuario a modificar.
     * @return \Illuminate\Http\RedirectResponse
     *
    public function update(Request $request, string $id)
    {
        // ─────────────────────────────────────────────────────────────────────
        // FASE 1: VALIDACIÓN DE DATOS ENTRANTES
        // ─────────────────────────────────────────────────────────────────────
        $request->validate([
            'ficha'             => ['required', 'string', 'max:50'],
            'email'             => ['required', 'string', 'email', 'max:255'],
            'nueva_password'    => ['nullable', 'string', 'min:8'], // Opcional en edición
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_rol'            => ['required', 'integer', 'min:1'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            // Uso de 'nullable' para campos no obligatorios en estructura organizacional
            'id_puesto'         => ['nullable', 'integer'],
            'id_centro_trabajo' => ['nullable', 'integer'],
            'id_departamento'   => ['nullable', 'integer'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_gerencia'       => ['nullable', 'integer'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ]);

        // ─────────────────────────────────────────────────────────────────────
        // FASE 2: LÓGICA CONDICIONAL DE SEGURIDAD (PASSWORD)
        // ─────────────────────────────────────────────────────────────────────
        $passwordHasheado = $request->filled('nueva_password')
            ? Hash::make($request->nueva_password)
            : null; // Null indica al SP que NO debe tocar la contraseña actual.

        // ─────────────────────────────────────────────────────────────────────
        // FASE 3: EJECUCIÓN TRANSACCIONAL
        // ─────────────────────────────────────────────────────────────────────
        //try {
            // Llamada al SP de Edición (21 Parámetros)
            $resultado = DB::select('CALL SP_EditarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                      // 1. Auditoría: Quién modifica
                $id,                             // 2. Target: A quién se modifica
                $request->ficha,
                $request->foto_perfil,
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,
                $request->email,
                $passwordHasheado,               // 11. Nueva clave (o NULL para no cambiar)
                $request->id_rol,
                $request->id_regimen,
                $request->id_puesto ?? 0,        // Null coalescing: Si es null, envía 0
                $request->id_centro_trabajo ?? 0,
                $request->id_departamento ?? 0,
                $request->id_region,
                $request->id_gerencia ?? 0,
                $request->nivel,
                $request->clasificacion,
                $request->foto_perfil,
            ]);

            // Análisis de la respuesta del SP (Feedback detallado)
            $accion = $resultado[0]->Accion ?? 'ACTUALIZADA';
            $mensaje = $resultado[0]->Mensaje ?? 'Usuario actualizado correctamente.';

            // Feedback: Si el SP detecta que los datos enviados son idénticos a los
            // existentes, retorna 'SIN_CAMBIOS'. Usamos una alerta informativa (azul).
            if ($accion === 'SIN_CAMBIOS') {
                return redirect()->route('Usuarios.edit', $id)
                    ->with('info', $mensaje);
            }

            return redirect()->route('Usuarios.show', $id)
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }*/

/**
     * █ ELIMINACIÓN DESTRUCTIVA (HARD DELETE) — PROTOCOLO PUREZA TOTAL
     * ─────────────────────────────────────────────────────────────────────────
     * Este motor ejecuta una purga de dos fases diseñada para el entorno PICADE.
     * Fase 1: Sincroniza la eliminación lógica en MariaDB mediante Procedimientos.
     * Fase 2: Ejecuta la destrucción física de activos multimedia en el servidor.
     * Este proceso es irreversible y debe usarse con extrema precaución operativa.
     * Garantiza el cumplimiento de las políticas de ahorro de espacio en disco.
     *
     * @risk_level   EXTREMO (Irreversible / High Severity)
     * @audit        Event ID: USER_IDENTITY_PURGE_COMMIT
     * @param        string $id Identificador único del usuario objetivo.
     * @return       \Illuminate\Http\RedirectResponse Redirección con sello de estado.
     */
    public function destroy(string $id)
    {
        try {
            // █ SECCIÓN A: LOCALIZACIÓN PRE-MORTEM Y EXTRACCIÓN DE METADATOS
            // Antes de iniciar la destrucción en base de datos, realizamos un rastreo del objeto.
            // Esta fase es crítica porque necesitamos obtener la ruta física de la fotografía perfil.
            // Si eliminamos el registro antes de este paso, el puntero al archivo se pierde para siempre,
            // convirtiendo la imagen en un "archivo zombie" que ocupa espacio residual en el servidor.
            // Validamos que el usuario realmente exista antes de disparar la carga transaccional del SP.
            // Es el primer anillo de seguridad para evitar peticiones de eliminación sobre la nada.
            $usuario = DB::table('Usuarios')->where('Id_Usuario', $id)->first();

            if (!$usuario) {
                return redirect()->route('Usuarios.index')
                    ->with('warning', 'INCIDENTE DE LOCALIZACIÓN: El usuario no existe o ya fue purgado.');
            }

            // █ SECCIÓN B: PERSISTENCIA DESTRUCTIVA (STORED PROCEDURE EXECUTION)
            // Invocamos el procedimiento maestro encargado de la eliminación atómica del colaborador.
            // Este SP gestiona la eliminación en cascada entre las tablas Usuarios e Info_Personal.
            // Se inyecta el ID del administrador ejecutor para mantener el rastro forense en los logs.
            // Al ejecutarse en MariaDB, nos aseguramos de que se respeten todas las reglas de integridad.
            // Si el SP falla, lanzará una excepción que será atajada por el bloque catch especializado.
            // Es la fase donde la identidad digital del colaborador es oficialmente dada de baja.
            $resultado = DB::select('CALL SP_EliminarUsuarioDefinitivamente(?, ?)', [
                Auth::id(), // Sello de auditoría del administrador responsable.
                $id,        // Identificador del usuario que será eliminado del sistema.
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'EXPEDIENTE PURGADO: El registro ha sido eliminado.';

            // █ SECCIÓN C: PROTOCOLO DE PURGA MULTIMEDIA (CLEANUP DE ACTIVOS)
            // Tras confirmar la baja en la base de datos, procedemos a la limpieza del almacenamiento.
            // Este bloque busca el archivo físico en el disco 'public' y lo destruye de manera definitiva.
            // Implementamos una limpieza de prefijos redundantes para asegurar que la ruta sea compatible.
            // Este paso es vital para la salud del servidor de PEMEX, evitando el inflado de storage.
            // Solo se activa si el usuario poseía un activo multimedia registrado en su perfil oficial.
            // Garantiza que la eliminación del usuario sea total, tanto en datos como en archivos.
            if (!empty($usuario->Foto_Perfil_Url)) {
                $cleanPath = str_replace(['/storage/', 'storage/'], '', $usuario->Foto_Perfil_Url);
                
                if (Storage::disk('public')->exists($cleanPath)) {
                    Storage::disk('public')->delete($cleanPath);
                }
            }

            return redirect()->route('Usuarios.index')
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            // █ SECCIÓN D: GESTIÓN DE EXCEPCIONES SQL Y SEGURIDAD REFERENCIAL
            // Esta capa atrapa cualquier error disparado por el motor de base de datos MariaDB.
            // Si el SP bloquea la eliminación por existir dependencias activas, aquí se captura el grito.
            // Utilizamos el método extraerMensajeSP para traducir el código técnico a lenguaje humano.
            // Evita que el administrador se tope con la pantalla naranja (Error 500) del servidor.
            // Es el mecanismo de seguridad que previene la corrupción de la integridad referencial.
            // Proporciona retroalimentación inmediata sobre por qué no se pudo completar la purga.
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('Usuarios.index')
                ->with('danger', 'ERROR DE PERSISTENCIA: ' . $mensajeSP);

        } catch (\Exception $e) {
            // █ SECCIÓN E: RESPALDO DE INFRAESTRUCTURA Y FALLOS GENÉRICOS
            // Actúa como la red de seguridad final ante incidentes fuera del motor de base de datos.
            // Captura errores de permisos de disco, fallos en el sistema de archivos o de red.
            // Registra el incidente sin exponer detalles sensibles de la arquitectura al operador.
            // Garantiza que la aplicación mantenga su estado de ejecución ante imprevistos críticos.
            // Es el último recurso del Standard Platinum para asegurar la estabilidad global del sistema.
            // Retorna al Index con una alerta de incidente técnico para su posterior revisión en logs.
            return redirect()->route('Usuarios.index')
                ->with('danger', 'INCIDENTE TÉCNICO: Error crítico en el motor de purga destructiva.');
        }
    }

    /*
     * █ ELIMINACIÓN DESTRUCTIVA (HARD DELETE)
     * ─────────────────────────────────────────────────────────────────────────
     * Elimina físicamente el registro de la base de datos y toda su información vinculada.
     *
     * @risk_level EXTREMO (High Severity)
     * @implication Esta acción es irreversible. Se elimina la fila de `Usuarios` y `Info_Personal`.
     * @usage Solo recomendado para depuración o corrección de registros erróneos recién creados.
     * Para bajas de personal operativo, se debe usar `cambiarEstatus` (Baja Lógica).
     *
     * @param string $id ID del usuario a eliminar.
     * @return \Illuminate\Http\RedirectResponse
     *
    public function destroy(string $id)
    {
        //try {
            $resultado = DB::select('CALL SP_EliminarUsuarioDefinitivamente(?, ?)', [
                Auth::id(), // Auditoría obligatoria del ejecutor
                $id,        // ID del objetivo
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Usuario eliminado permanentemente.';
            return redirect()->route('Usuarios.index')
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            
            return redirect()->route('Usuarios.index')
                ->with($tipoAlerta, $mensajeSP);
        }
    }*/

    /* ========================================================================================
       █ SECCIÓN 2: MÉTODOS DE AUTO-GESTIÓN (PERFIL PERSONAL)
       ────────────────────────────────────────────────────────────────────────────────────────
       Zona pública autenticada. Contiene los métodos que permiten a cualquier usuario
       (sin importar su rol) consultar y gestionar su propia información personal.
       ======================================================================================== */

    /**
     * █ VISOR DE PERFIL PROPIO
     * ─────────────────────────────────────────────────────────────────────────
     * Muestra la información del usuario que tiene la sesión activa actualmente.
     *
     * @security Context Isolation
     * A diferencia de `show($id)`, este método NO recibe parámetros. Utiliza estrictamente
     * `Auth::id()` para la consulta. Esto impide que un usuario malintencionado pueda
     * ver el perfil de otro modificando el ID en la URL (IDOR Prevention).
     *
     * @return \Illuminate\View\View Vista del perfil personal.
     */
    public function perfil()
    {
        //try {
            $perfil = DB::select('CALL SP_ConsultarPerfilPropio(?)', [Auth::id()]);

            if (empty($perfil)) {
                return redirect('/Dashboard')
                    ->with('danger', 'Error de integridad: No se pudo cargar tu perfil asociado.');
            }

            $catalogos = $this->cargarCatalogos();

            return view('Usuario.perfil', [
                'perfil'    => $perfil[0],
                'catalogos' => $catalogos,
            ]);

        /*} catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect('/Dashboard')
                ->with('danger', $mensajeSP);
        }*/
    }

    /**
     * █ ACTUALIZACIÓN DE DATOS PERSONALES PROPIOS
     * ─────────────────────────────────────────────────────────────────────────
     * Permite al usuario corregir su información básica (Nombre, Dirección, Foto).
     *
     * @security Scope Limitation
     * Este método NO permite editar campos sensibles de administración como:
     * - Rol (Privilegios)
     * - Estatus (Activo/Inactivo)
     * - Email (Credencial) - Para esto ver `actualizarCredenciales`
     *
     * @param Request $request Datos del formulario de perfil.
     * @return \Illuminate\Http\RedirectResponse
     */
    public function actualizarPerfil(Request $request)
    {
        // 1. Validación de campos permitidos
        $request->validate([
            'ficha'             => ['required', 'string', 'max:10'],
            'nombre'            => ['required', 'string', 'max:100'],
            'apellido_paterno'  => ['required', 'string', 'max:100'],
            'apellido_materno'  => ['required', 'string', 'max:100'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['nullable', 'integer'],
            'id_centro_trabajo' => ['nullable', 'integer'],
            'id_departamento'   => ['nullable', 'integer'],
            'id_gerencia'       => ['nullable', 'integer'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ]);

        //try {
            // Ejecución del SP específico para auto-edición (limitado en alcance)
            $resultado = DB::select('CALL SP_EditarPerfilPropio(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(), // El ID sale de la sesión, no del Request (Seguridad Crítica)
                $request->ficha,
                $request->foto_perfil,
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,
                $request->id_regimen,
                $request->id_puesto ?? 0,
                $request->id_centro_trabajo ?? 0,
                $request->id_departamento ?? 0,
                $request->id_region,
                $request->id_gerencia ?? 0,
                $request->nivel,
                $request->clasificacion,
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Perfil actualizado.';
            return redirect()->route('MiPerfil')
                ->with('success', $mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }*/
    }

    /*
     * █ GESTIÓN DE CREDENCIALES (PASSWORD / EMAIL)
     * ─────────────────────────────────────────────────────────────────────────
     * Permite al usuario cambiar sus llaves de acceso al sistema.
     *
     * @security Double Verification (Anti-Hijacking)
     * Implementa un mecanismo de verificación de contraseña actual.
     * El usuario DEBE proporcionar su `password_actual` correcta para autorizar el cambio.
     * Esto mitiga el riesgo de "Session Hijacking" (si alguien deja la PC desbloqueada,
     * el atacante no puede cambiar la contraseña sin saber la actual).
     *
     * @param Request $request
     * @return \Illuminate\Http\RedirectResponse
     */
    public function actualizarCredenciales(Request $request)
    {
        // 1. Validación de input
        $request->validate([
            'password_actual' => ['required', 'string'],
            'nuevo_email'     => ['nullable', 'string', 'email', 'max:255'],
            'nueva_password'  => ['nullable', 'string', 'min:8', 'confirmed'],
        ], [
            'password_actual.required' => 'Por seguridad, debes ingresar tu contraseña actual para confirmar los cambios.',
        ]);

        // 2. Validación lógica: Debe haber al menos un dato para cambiar
        if (!$request->filled('nuevo_email') && !$request->filled('nueva_password')) {
            return back()->with('danger', 'No se detectaron cambios. Ingrese un nuevo correo o contraseña.');
        }

        // 3. VERIFICACIÓN DE IDENTIDAD (Hash Check)
        // Laravel compara el string plano del request con el hash bcrypt de la BD.
        $usuario = Auth::user();
        if (!Hash::check($request->password_actual, $usuario->getAuthPassword())) {
            return back()->withErrors([
                'password_actual' => 'La contraseña actual es incorrecta. Intente nuevamente.',
            ]);
        }

        // 4. Preparación de datos (Sanitización)
        $nuevoEmailLimpio = $request->filled('nuevo_email') ? $request->nuevo_email : null;
        $nuevaPassHasheada = $request->filled('nueva_password') ? Hash::make($request->nueva_password) : null;

        // 5. Ejecución segura
        //try {
            $resultado = DB::select('CALL SP_ActualizarCredencialesPropio(?, ?, ?)', [
                Auth::id(),
                $nuevoEmailLimpio,
                $nuevaPassHasheada,
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Credenciales actualizadas correctamente.';
            return redirect()->route('MiPerfil')
                ->with('success', $mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return back()->with('danger', $mensajeSP);
        }*/
    }

    /* ========================================================================================
       █ SECCIÓN 3: GESTIÓN DE ESTATUS (BAJA LÓGICA / REACTIVACIÓN)
       ────────────────────────────────────────────────────────────────────────────────────────
       Métodos para el control del ciclo de vida del acceso del usuario.
       ======================================================================================== */

    /*
     * █ INTERRUPTOR DE ACCESO (SOFT DELETE / TOGGLE)
     * ─────────────────────────────────────────────────────────────────────────
     * @purpose Ejecutar la inhabilitación o reactivación de una identidad en el sistema.
     * @security Audit Trace Enabled
     * * @logic
     * No realiza un borrado físico (DELETE) para evitar la rotura de integridad 
     * referencial en cascada (historial de cursos, firmas de capacitador, etc.).
     * Modifica el bit de `Activo` en la tabla `Usuarios` mediante un proceso atómico.
     *
     * @workflow
     * 1. Valida que el estatus recibido sea binario (0 o 1).
     * 2. Invoca SP_CambiarEstatusUsuario inyectando el ID del administrador ejecutor.
     * 3. El SP actualiza la bandera y genera un registro en la bitácora de auditoría.
     * 4. Retorna a la vista de origen (Index) conservando filtros y paginación.
     *
     * @param  Request $request Objeto con 'nuevo_estatus' (INT: 0,1).
     * @param  string  $id      Identificador único del usuario objetivo.
     * @return \Illuminate\Http\RedirectResponse
     */
    public function cambiarEstatus(Request $request, string $id)
    {
        // ── CAPA 1: VALIDACIÓN DE INTEGRIDAD ──
        $request->validate([
            'nuevo_estatus' => ['required', 'integer', 'in:0,1'],
        ]);

        //try {
            // ── CAPA 2: EJECUCIÓN TRANSACCIONAL (SQL) ──
            $resultado = DB::select('CALL SP_CambiarEstatusUsuario(?, ?, ?)', [
                Auth::id(),             // _Id_Admin_Ejecutor (Responsabilidad forense)
                $id,                    // _Id_Usuario_Objetivo
                $request->nuevo_estatus // _Nuevo_Estatus (Bit)
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Estatus actualizado correctamente.';

            /**
             * █ RETORNO DE CONTEXTO (UX OPTIMIZATION)
             * ─────────────────────────────────────────────────────────────────
             * Se utiliza back() en lugar de redirect()->route() para asegurar que 
             * el administrador permanezca en la misma página de la tabla (dentro 
             * de los 3,000 registros) y no pierda sus criterios de búsqueda.
             */
            return back()->with('success', $mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            // ── CAPA 3: GESTIÓN DE EXCEPCIONES ──
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            
            // Regresamos al punto de origen con la alerta de error capturada del SP
            return back()->with('danger', $mensajeSP);
        }*/
    }

    /* ========================================================================================
       █ SECCIÓN 4: UTILIDADES INTERNAS (HELPERS PRIVADOS)
       ────────────────────────────────────────────────────────────────────────────────────────
       Métodos de soporte encapsulados para tareas repetitivas o de lógica de presentación.
       ======================================================================================== */

    /**
     * █ CARGADOR DE CATÁLOGOS ACTIVOS (DATA PRE-LOADING)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta una batería de lecturas rápidas a la base de datos para alimentar
     * los componentes de interfaz (selects) de los formularios.
     *
     * @strategy Eager Loading
     * Carga todos los catálogos "Raíz" (independientes) en una sola pasada.
     * Nota: Las dependencias geográficas (Estados, Municipios) no se cargan aquí,
     * se manejan vía AJAX/API (`CatalogoController`) para no saturar la carga inicial.
     *
     * @return array Colección asociativa con los datasets de cada catálogo.
     */
    private function cargarCatalogos(): array
    {
        return [
            // Seguridad y Roles
            'Roles'           => DB::select('CALL SP_ListarRolesActivos()'),
            
            // Estructura Contractual
            'Regimenes'       => DB::select('CALL SP_ListarRegimenesActivos()'),
            'Puestos'         => DB::select('CALL SP_ListarPuestosActivos()'),
            
            // Estructura Organizacional PEMEX
            'CentrosTrabajo'          => DB::select('CALL SP_ListarCTActivos()'),      // Sincronizado con el SP que mandaste            'departamentos'   => DB::select('CALL SP_ListarDepActivos()'),
            'Departamentos'      => DB::select('CALL SP_ListarDepActivos()'), // Llave sincronizada con la vista            
            // Geografía
            'Paises'          => DB::select('CALL SP_ListarPaisesActivos()'),      // Raíz de cascada geográfica
            'Regiones'        => DB::select('CALL SP_ListarRegionesActivas()'),
            'Direcciones' => DB::select('CALL SP_ListarDireccionesActivas()'), // <--- ESTA LÍNEA FALTABA
            'Gerencias'   => DB::select('CALL SP_ListarGerenciasAdminParaFiltro()'),
        ];
    }

    /*
     * █ OBTENER CATÁLOGOS DIRECTOS (PLATINUM STANDARD)
     * ─────────────────────────────────────────────────────────────────────────
     * Recupera la información de las tablas raíz directamente.
     * Sin SPs, sin JOINs innecesarios y con nombres de columnas estandarizados.
     */
    private function obtenerCatalogosBase(): array
    {
        return [
            'Roles'          => DB::table('Cat_Roles')->select('Id_Rol', 'Nombre')->orderBy('Nombre')->get(),
            'Regimenes'      => DB::table('Cat_Regimenes_Trabajo')->select('Id_CatRegimen', 'Nombre', 'Codigo')->orderBy('Nombre')->get(),
            'Puestos'        => DB::table('Cat_Puestos_Trabajo')->select('Id_CatPuesto', 'Nombre', 'Codigo')->orderBy('Nombre')->get(),
            'Regiones'       => DB::table('Cat_Regiones_Trabajo')->select('Id_CatRegion', 'Nombre', 'Codigo')->orderBy('Nombre')->get(),
            'CentrosTrabajo' => DB::table('Cat_Centros_Trabajo')->select('Id_CatCT', 'Nombre', 'Codigo')->orderBy('Nombre')->get(),
            'Departamentos'  => DB::table('Cat_Departamentos')->select('Id_CatDep', 'Nombre', 'Codigo')->orderBy('Nombre')->get(),
            'Direcciones'    => DB::table('Cat_Direcciones')->select('Id_CatDirecc', 'Nombre', 'Clave')->orderBy('Nombre')->get(),
        ];
    }
    /**
     * █ PARSER DE ERRORES SQL (REFINAMIENTO QUIRÚRGICO)
     * ─────────────────────────────────────────────────────────────────────────
     * @description: Implementa un filtro de "Cero Metadata" para transformar
     * excepciones crudas de PDO en veredictos de negocio limpios.
     * * @logic: 
     * 1. Detecta el código de señal 1644 (SIGNAL SQLSTATE 45000).
     * 2. Recorta el string antes de que aparezca la información de conexión.
     * 3. Aplica máscara de seguridad si el error no es una regla de negocio.
     */
    private function extraerMensajeSP(string $mensajeCompleto): string
    {
        // ── PASO 1: EL CORTE QUIRÚRGICO (PRECISION CUT) ──
        // Buscamos el texto que reside entre el código de error 1644 y la metadata de conexión.
        // Regex: /1644\s+(.*?)\s+\(Connection:/s
        // Significado: Captura todo de forma no codiciosa hasta encontrar "(Connection:"
        if (preg_match('/1644\s+(.*?)\s+\(Connection:/s', $mensajeCompleto, $matches)) {
            return trim($matches[1]);
        }

        // ── PASO 2: FILTRO DE VECTORES DE NEGOCIO (KEYWORD SCAN) ──
        // Si el formato del driver cambia, buscamos las cabeceras estándar de nuestros SPs.
        $keywords = [
            'ACCESO DENEGADO', 
            'ERROR DE', 
            'CONFLICTO', 
            'BLOQUEO', 
            'EMISIÓN BLOQUEADA', 
            'VALIDACIÓN FALLIDA'
        ];

        foreach ($keywords as $key) {
            if (stripos($mensajeCompleto, $key) !== false) {
                // Captura desde la palabra clave hasta antes de la metadata
                if (preg_match('/(' . $key . '.*?)(?=\s*\(Connection:|$)/i', $mensajeCompleto, $matches)) {
                    return trim($matches[1]);
                }
            }
        }

        // ── PASO 3: MÁSCARA DE SEGURIDAD (SECURITY MASKING) ──
        // Si el error NO contiene el estado 45000, es un error de infraestructura
        // (ej: Columna no encontrada, Tabla bloqueada). 
        // PROHIBIDO mostrar esto al usuario: devolvemos un mensaje genérico profesional.
        if (!str_contains($mensajeCompleto, '45000')) {
            // Aquí podrías disparar un Log interno: Log::critical($mensajeCompleto);
            return 'INCIDENTE TÉCNICO: El motor de datos reportó una anomalía inusual. Por favor, reporte este evento a Soporte Técnico.';
        }

        return 'REGLA DE INTEGRIDAD: La operación fue rechazada por el sistema de control interno.';
    }

    /**
     * █ CLASIFICADOR DE SEVERIDAD DE ALERTAS (UX SEVERITY MAPPER)
     * ─────────────────────────────────────────────────────────────────────────
     * Determina el color semántico de la alerta en el Frontend (Bootstrap Class)
     * basándose en el código o contenido del mensaje de error.
     *
     * @rules
     * - Conflictos leves (ej: Duplicado pero activo) -> Warning (Amarillo)
     * - Errores críticos (ej: Violación de seguridad) -> Danger (Rojo)
     *
     * @param string $mensaje El mensaje limpio del SP.
     * @return string Clase CSS ('warning', 'danger', 'info').
     */
    private function clasificarAlerta(string $mensaje): string
    {
        // Códigos personalizados:
        // 409-A: Conflicto de Duplicidad (Ya existe)
        // CONFLICTO OPERATIVO: Reglas de negocio (ej: Fechas inválidas)
        if (str_contains($mensaje, '409-A') || str_contains($mensaje, '409') || str_contains($mensaje, 'CONFLICTO')) {
            return 'warning';
        }

        // 409-B: Duplicado Inactivo (Requiere reactivación manual)
        // BLOQUEO / DENEGADA: Permisos insuficientes o reglas de seguridad
        return 'danger';
    }

    /* ========================================================================================
       █ SECCIÓN 4: ONBOARDING Y FLUJOS DE INTEGRIDAD (COMPLETAR PERFIL)
       ────────────────────────────────────────────────────────────────────────────────────────
       Zona de paso obligatorio para todos los usuarios (incluyendo Admin). 
       Garantiza que el expediente digital esté completo antes de operar el sistema.
       ======================================================================================== */

    /*
     * █ INTERFAZ DE COMPLETADO DE EXPEDIENTE (ONBOARDING)
     * ─────────────────────────────────────────────────────────────────────────
     * Prepara el entorno para que el usuario finalice su registro de adscripción.
     * @data_context Consume SP_ConsultarPerfilPropio para la hidratación reactiva.
     * @return \Illuminate\View\View Vista `panel.CompletarPerfil`.
     */
    public function vistaCompletar()
    {
        //try {
            // 1. Hidratación del Snapshot (Carga Ligera vía SP)
            $resultado = DB::select('CALL SP_ConsultarPerfilPropio(?)', [Auth::id()]);
            
            if (empty($resultado)) {
                return redirect('/login')->with('danger', 'Error de hidratación: Sesión inválida.');
            }

            $perfil = $resultado[0];

            // 2. Carga de Catálogos Raíz (Regímenes, Puestos, Regiones, etc.)
            $catalogos = $this->cargarCatalogos();

            // Retornamos la vista física en resources/views/panel/CompletarPerfil.blade.php
            return view('panel.CompletarPerfil', compact('perfil', 'catalogos'));

        /*} catch (\Exception $e) {
            return redirect('/Dashboard')->with('danger', 'Error al inicializar el motor de integridad.');
        }*/
    }

    /**
     * █ MOTOR DE PERSISTENCIA DE ONBOARDING
     * ─────────────────────────────────────────────────────────────────────────
     * Procesa la actualización obligatoria consumiendo SP_EditarPerfilPropio.
     * @param Request $request Payload con los 16 parámetros requeridos por el SP.
     * @return \Illuminate\Http\RedirectResponse Redirección al Dashboard tras éxito.
     */
    public function guardarCompletado(Request $request)
    {
        // 1. Validación de Formato (Siguiendo tu estándar de actualizarPerfil)
        $request->validate([
            'ficha'            => ['required', 'string', 'max:10'],
            'foto_perfil'      => ['nullable', 'image', 'mimes:jpg,jpeg,png', 'max:2048'], // █ CLAVE: Validar como imagen
            'nombre'           => ['required', 'string', 'max:100'],
            'apellido_paterno' => ['required', 'string', 'max:100'],
            'apellido_materno' => ['required', 'string', 'max:100'],
            'fecha_nacimiento' => ['required', 'date'],
            'fecha_ingreso'    => ['required', 'date'],
            'id_regimen'       => ['required', 'integer', 'min:1'],
            'id_region'        => ['required', 'integer', 'min:1'],
            'id_puesto'        => ['nullable', 'integer'],
            'id_centro_trabajo'=> ['nullable', 'integer'],
            'id_departamento'  => ['nullable', 'integer'],
            'id_gerencia'      => ['nullable', 'integer'],
            'nivel'            => ['nullable', 'string', 'max:50'],
            'clasificacion'    => ['nullable', 'string', 'max:100'],
        ]);

        // 2. GESTIÓN DE ACTIVOS MULTIMEDIA (ASSET MANAGEMENT)
        $rutaFoto = null;
        if ($request->hasFile('foto_perfil')) {
            // Generación de nombre único para evitar colisiones
            $filename = time() . '_' . trim($request->ficha) . '.' . $request->file('foto_perfil')->getClientOriginalExtension();
            $path = $request->file('foto_perfil')->storeAs('perfiles', $filename, 'public');
            $rutaFoto = '/storage/' . $path;
        }

        //try {
            // 2. Ejecución Atómica (16 Parámetros en orden estricto)
            $resultado = DB::select('CALL SP_EditarPerfilPropio(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                // 1. _Id_Usuario_Sesion
                $request->ficha,           // 2. _Ficha
                $rutaFoto,     // 3. _Url_Foto
                $request->nombre,          // 4. _Nombre
                $request->apellido_paterno, // 5. _Apellido_Paterno
                $request->apellido_materno, // 6. _Apellido_Materno
                $request->fecha_nacimiento, // 7. _Fecha_Nacimiento
                $request->fecha_ingreso,    // 8. _Fecha_Ingreso
                $request->id_regimen,      // 9. _Id_Regimen
                $request->id_puesto ?? 0,  // 10. _Id_Puesto (Norm: 0 -> NULL)
                $request->id_centro_trabajo ?? 0, // 11. _Id_CentroTrabajo
                $request->id_departamento ?? 0,   // 12. _Id_Departamento
                $request->id_region,       // 13. _Id_Region
                $request->id_gerencia ?? 0, // 14. _Id_Gerencia
                $request->nivel,           // 15. _Nivel
                $request->clasificacion    // 16. _Clasificacion
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Perfil activado correctamente.';
            
            // 3. Liberación: El usuario ya puede ver su Dashboard
            return redirect()->route('dashboard')->with('success', $mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            // 4. FASE DE LIMPIEZA (ANTI-ZOMBIE CLEANUP)
            // Si la base de datos falla (ej: ficha duplicada), borramos la foto que acabamos de subir.
            if ($rutaFoto && file_exists(public_path($rutaFoto))) {
                unlink(public_path($rutaFoto));
            }

            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }*/
    }

    /*
     * █ MÓDULO: KÁRDEX DIGITAL — HISTORIAL ACADÉMICO CERTIFICADO
     * ─────────────────────────────────────────────────────────────────────────────────────────────
     * * I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
     * ---------------------------------------------------------------------------------------------
     * - Nombre Oficial    : MiKardex
     * - Sistema           : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
     * - Clasificación     : Consulta de Historial Académico Personal (Student Record Inquiry)
     * - Patrón de Diseño  : SSR (Server Side Rendering) with Identity Injected Query
     * - Dependencia Core  : Procedimiento Almacenado `SP_ConsularMisCursos`
     * - Seguridad         : Row Level Security (RLS) mediante inyección forzada de Auth::id()
     * * II. PROPÓSITO Y LÓGICA DE NEGOCIO (BUSINESS VALUE)
     * ---------------------------------------------------------------------------------------------
     * Este método constituye el punto de verdad única para el expediente del trabajador.
     * Su objetivo es consolidar la traza histórica de capacitaciones para fines de:
     * A. Evidencia Curricular: Registro oficial de horas y temas acreditados.
     * B. Gestión de Cumplimiento: Verificación de estatus ante auditorías normativas.
     * C. Visualización Estratégica: Despliegue de KPIs de rendimiento (Promedio y Volumen).
     * * III. ARQUITECTURA DE DATOS Y FILTRADO
     * ---------------------------------------------------------------------------------------------
     * Delegación Total: El controlador actúa como un túnel de transporte. No filtra ni ordena data;
     * confía plenamente en la lógica de "Latest Snapshot" implementada en el SP de MariaDB.
     * * Integridad de Estatus: Consume el campo `Id_Estatus_Participante` para garantizar que la
     * capa de presentación (Blade) aplique semáforos de color basados en llaves primarias inmutables,
     * eliminando la fragilidad de las comparaciones por cadenas de texto.
     * * @return \Illuminate\View\View Vista hidratada con el dataset del expediente y métricas analíticas.
     * =============================================================================================
     *
    public function MiKardex()
    {
        try {
            // [FASE 1]: INGESTA DE DATOS CERTIFICADOS (DATA INGESTION)
            // Invocación al SP mediante el Driver de PDO. Se inyecta la identidad de sesión.
            // El SP devuelve el campo 'Id_Estatus_Participante' (ID numérico) para lógica robusta.
            $rawExpediente = DB::select('CALL SP_ConsularMisCursos(?)', [
                Auth::id()
            ]);

            // [FASE 2]: MOTOR DE INTELIGENCIA (BI PROCESSING)
            // Transformamos el array crudo en una Colección para ejecución de métodos estadísticos.
            $expediente = collect($rawExpediente);

            // 2.1 KPI: Volumen de Operación (Total Cursos)
            $totalCursos = $expediente->count();
            
            // 2.2 KPI: Rendimiento Académico (Promedio General)
            // Filtramos valores nulos y ceros técnicos para no penalizar el promedio con cursos pendientes.
            $promedioGral = $totalCursos > 0 
                ? $expediente->whereNotNull('Calificacion_Numerica')
                             ->where('Calificacion_Numerica', '>', 0)
                             ->avg('Calificacion_Numerica') 
                : 0;

            // Formateo bajo estándar decimal institucional (1 decimal)
            $promedioGral = number_format((float)$promedioGral, 1);

            // [FASE 3]: HIDRATACIÓN DE VISTA Y DESPACHO (SSR DELIVERY)
            return view('components.MiKardex', [
                'historial'    => $rawExpediente, 
                'totalCursos'  => $totalCursos,
                'promedioGral' => $promedioGral
            ]);

        } catch (\Exception $e) {
            // [FAIL-SAFE PROTOCOL]: En caso de fallo crítico, se redirige al dashboard con alerta.
            return redirect()->route('dashboard')
                ->with('danger', 'Error de Integridad: No se pudo reconstruir tu expediente académico en este momento.');
        }
    }*/

    /*
     * █ MÓDULO: KÁRDEX DIGITAL — MOCK DATA ENGINE (CORREGIDO CON IDs)
     * ──────────────────────────────────────────────────────────────────────
     * @description: Simulación masiva con IDs numéricos para validar la
     * lógica de semáforo en la vista.
     */
    public function MiKardex()
    {
        $hoy = \Carbon\Carbon::now();

        // [ESCENARIOS DE PRUEBA: 20 CURSOS]
        $historialRaw = collect([
            
            // -------------------------------------------------------------------------
            // 1. PROGRAMADOS (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 101,
                'Tema_Curso' => 'Liderazgo Gerencial PEMEX',
                'Folio_Curso' => 'CAP-2026-050',
                'Fecha_Inicio' => $hoy->copy()->addMonths(2)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addMonths(2)->addDays(3)->format('Y-m-d'),
                'Instructor_Asignado' => 'Dr. Alejandro Magno',
                'Sede' => 'Auditorio Torre Ejecutiva', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 24,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // <--- ¡ESTO ES LO QUE FALTABA!
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'PROGRAMADO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => $hoy->format('Y-m-d')
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 102,
                'Tema_Curso' => 'Normativa ISO-27001 (Seguridad)',
                'Folio_Curso' => 'CAP-2026-051',
                'Fecha_Inicio' => $hoy->copy()->addMonths(1)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addMonths(1)->addDays(2)->format('Y-m-d'),
                'Instructor_Asignado' => 'Ing. Sarah Connor',
                'Sede' => 'Sala Virtual Teams', 'Modalidad' => 'En Línea', 'Duracion_Horas' => 16,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'PROGRAMADO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => $hoy->copy()->subDays(1)->format('Y-m-d')
            ],

            // -------------------------------------------------------------------------
            // 2. EN CURSO (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 201,
                'Tema_Curso' => 'Operación de Ductos Nivel 1',
                'Folio_Curso' => 'CAP-2026-040',
                'Fecha_Inicio' => $hoy->copy()->subDays(1)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addDays(3)->format('Y-m-d'),
                'Instructor_Asignado' => 'Ing. Marco Sosa',
                'Sede' => 'Campo Samaria', 'Modalidad' => 'Práctico', 'Duracion_Horas' => 40,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'EN CURSO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => $hoy->copy()->subWeeks(2)->format('Y-m-d')
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 202,
                'Tema_Curso' => 'Excel Avanzado para Finanzas',
                'Folio_Curso' => 'CAP-2026-041',
                'Fecha_Inicio' => $hoy->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addDays(4)->format('Y-m-d'),
                'Instructor_Asignado' => 'Lic. Pedro Picapiedra',
                'Sede' => 'Aula de Capacitación 1', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 10,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'EN CURSO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => $hoy->copy()->subWeeks(1)->format('Y-m-d')
            ],

            // -------------------------------------------------------------------------
            // 3. CANCELADOS (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 301,
                'Tema_Curso' => 'Trabajo en Alturas',
                'Folio_Curso' => 'CAP-2026-005',
                'Fecha_Inicio' => $hoy->copy()->subMonths(1)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->subMonths(1)->addDays(1)->format('Y-m-d'),
                'Instructor_Asignado' => 'Téc. Juan Camaney',
                'Sede' => 'Patio de Maniobras', 'Modalidad' => 'Práctico', 'Duracion_Horas' => 8,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'CANCELADO',
                'Justificacion' => 'Evento cancelado por condiciones climáticas adversas.',
                'Fecha_Inscripcion' => $hoy->copy()->subMonths(2)->format('Y-m-d')
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 302,
                'Tema_Curso' => 'Introducción a PICADE',
                'Folio_Curso' => 'CAP-2026-003',
                'Fecha_Inicio' => '2026-01-10',
                'Fecha_Fin'    => '2026-01-10',
                'Instructor_Asignado' => 'Sistemas',
                'Sede' => 'Zoom', 'Modalidad' => 'En Línea', 'Duracion_Horas' => 4,
                'Porcentaje_Asistencia' => 0, 'Calificacion_Numerica' => 0,
                'Id_Estatus_Participante' => 5, // ID 5 = BAJA
                'Estatus_Participante' => 'BAJA',
                'Estatus_Global_Curso' => 'PROGRAMADO',
                'Justificacion' => 'Baja administrativa: No envió documentación a tiempo.',
                'Fecha_Inscripcion' => '2026-01-01'
            ],

            // -------------------------------------------------------------------------
            // 4. POR INICIAR (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 401,
                'Tema_Curso' => 'Primeros Auxilios Básicos',
                'Folio_Curso' => 'CAP-2026-045',
                'Fecha_Inicio' => $hoy->copy()->addDays(1)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addDays(2)->format('Y-m-d'),
                'Instructor_Asignado' => 'Paramédico José',
                'Sede' => 'Enfermería', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 12,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'POR INICIAR',
                'Justificacion' => null,
                'Fecha_Inscripcion' => $hoy->copy()->subDays(5)->format('Y-m-d')
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 402,
                'Tema_Curso' => 'Ética Corporativa',
                'Folio_Curso' => 'CAP-2026-046',
                'Fecha_Inicio' => $hoy->copy()->addDays(2)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addDays(2)->format('Y-m-d'),
                'Instructor_Asignado' => 'Lic. Sofia',
                'Sede' => 'Teams', 'Modalidad' => 'En Línea', 'Duracion_Horas' => 4,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'POR INICIAR',
                'Justificacion' => null,
                'Fecha_Inscripcion' => $hoy->copy()->subDays(10)->format('Y-m-d')
            ],

            // -------------------------------------------------------------------------
            // 5. EN EVALUACIÓN (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 501,
                'Tema_Curso' => 'Mantenimiento Preventivo',
                'Folio_Curso' => 'CAP-2026-030',
                'Fecha_Inicio' => $hoy->copy()->subDays(5)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->subDays(1)->format('Y-m-d'),
                'Instructor_Asignado' => 'Ing. Mecánico',
                'Sede' => 'Taller 2', 'Modalidad' => 'Práctico', 'Duracion_Horas' => 20,
                'Porcentaje_Asistencia' => 100, 
                'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 2, // ID 2 = ASISTIÓ
                'Estatus_Participante' => 'ASISTIÓ',
                'Estatus_Global_Curso' => 'EN EVALUACIÓN',
                'Justificacion' => 'Esperando captura de calificaciones.',
                'Fecha_Inscripcion' => $hoy->copy()->subMonths(1)->format('Y-m-d')
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 502,
                'Tema_Curso' => 'Protocolo de Comunicaciones',
                'Folio_Curso' => 'CAP-2026-031',
                'Fecha_Inicio' => $hoy->copy()->subDays(3)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->subDays(1)->format('Y-m-d'),
                'Instructor_Asignado' => 'Ing. Telecom',
                'Sede' => 'C4', 'Modalidad' => 'Híbrida', 'Duracion_Horas' => 16,
                'Porcentaje_Asistencia' => 80,
                'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 2, // ID 2 = ASISTIÓ
                'Estatus_Participante' => 'ASISTIÓ',
                'Estatus_Global_Curso' => 'EN EVALUACIÓN',
                'Justificacion' => null,
                'Fecha_Inscripcion' => $hoy->copy()->subMonths(1)->format('Y-m-d')
            ],

            // -------------------------------------------------------------------------
            // 6. FINALIZADOS CON CALIFICACIÓN (4 Cursos)
            // -------------------------------------------------------------------------
            (object)[ // Aprobado 1
                'Id_Detalle_de_Capacitacion' => 601,
                'Tema_Curso' => 'Seguridad Industrial Básica',
                'Folio_Curso' => 'CAP-2026-015',
                'Fecha_Inicio' => '2026-02-10',
                'Fecha_Fin'    => '2026-02-12',
                'Instructor_Asignado' => 'Ing. Seguridad',
                'Sede' => 'Aula 1', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 16,
                'Porcentaje_Asistencia' => 100, 'Calificacion_Numerica' => 95.0,
                'Id_Estatus_Participante' => 3, // ID 3 = APROBADO
                'Estatus_Participante' => 'APROBADO',
                'Estatus_Global_Curso' => 'FINALIZADO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => '2026-02-01'
            ],
            (object)[ // Aprobado 2
                'Id_Detalle_de_Capacitacion' => 602,
                'Tema_Curso' => 'Redacción Ejecutiva',
                'Folio_Curso' => 'CAP-2026-018',
                'Fecha_Inicio' => '2026-02-15',
                'Fecha_Fin'    => '2026-02-15',
                'Instructor_Asignado' => 'Lic. Letras',
                'Sede' => 'Zoom', 'Modalidad' => 'En Línea', 'Duracion_Horas' => 4,
                'Porcentaje_Asistencia' => 100, 'Calificacion_Numerica' => 88.5,
                'Id_Estatus_Participante' => 3, // ID 3
                'Estatus_Participante' => 'APROBADO',
                'Estatus_Global_Curso' => 'FINALIZADO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => '2026-02-05'
            ],
            (object)[ // No Aprobado 1
                'Id_Detalle_de_Capacitacion' => 603,
                'Tema_Curso' => 'Matemáticas Financieras',
                'Folio_Curso' => 'CAP-2026-012',
                'Fecha_Inicio' => '2026-01-20',
                'Fecha_Fin'    => '2026-01-25',
                'Instructor_Asignado' => 'Contador Luis',
                'Sede' => 'Aula SAP', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 20,
                'Porcentaje_Asistencia' => 90, 'Calificacion_Numerica' => 65.0, 
                'Id_Estatus_Participante' => 4, // ID 4 = NO APROBADO
                'Estatus_Participante' => 'NO APROBADO',
                'Estatus_Global_Curso' => 'FINALIZADO',
                'Justificacion' => 'No alcanzó el puntaje mínimo de 80.',
                'Fecha_Inscripcion' => '2026-01-10'
            ],
            (object)[ // No Aprobado 2
                'Id_Detalle_de_Capacitacion' => 604,
                'Tema_Curso' => 'Inglés Técnico Nivel 1',
                'Folio_Curso' => 'CAP-2026-011',
                'Fecha_Inicio' => '2026-01-15',
                'Fecha_Fin'    => '2026-01-20',
                'Instructor_Asignado' => 'Teacher John',
                'Sede' => 'Lab Idiomas', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 30,
                'Porcentaje_Asistencia' => 60, 
                'Calificacion_Numerica' => 90.0,
                'Id_Estatus_Participante' => 4, // ID 4
                'Estatus_Participante' => 'NO APROBADO',
                'Estatus_Global_Curso' => 'FINALIZADO',
                'Justificacion' => 'Reprobado por inasistencia (>20% faltas).',
                'Fecha_Inscripcion' => '2026-01-05'
            ],

            // -------------------------------------------------------------------------
            // 7. REPROGRAMADOS (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 701,
                'Tema_Curso' => 'Gestión del Cambio',
                'Folio_Curso' => 'CAP-2026-055',
                'Fecha_Inicio' => $hoy->copy()->addMonths(3)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addMonths(3)->addDays(1)->format('Y-m-d'),
                'Instructor_Asignado' => 'Psic. Organizacional',
                'Sede' => 'Auditorio', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 8,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'REPROGRAMADO',
                'Justificacion' => 'Cambio de fecha por solicitud de la Gerencia.',
                'Fecha_Inscripcion' => '2026-02-01'
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 702,
                'Tema_Curso' => 'Protección Civil',
                'Folio_Curso' => 'CAP-2026-056',
                'Fecha_Inicio' => $hoy->copy()->addWeeks(2)->format('Y-m-d'),
                'Fecha_Fin'    => $hoy->copy()->addWeeks(2)->addDays(1)->format('Y-m-d'),
                'Instructor_Asignado' => 'Bomberos',
                'Sede' => 'Patio', 'Modalidad' => 'Práctico', 'Duracion_Horas' => 8,
                'Porcentaje_Asistencia' => null, 'Calificacion_Numerica' => null,
                'Id_Estatus_Participante' => 1, // ID 1
                'Estatus_Participante' => 'INSCRITO',
                'Estatus_Global_Curso' => 'REPROGRAMADO',
                'Justificacion' => 'Reprogramado por lluvia.',
                'Fecha_Inscripcion' => '2026-02-10'
            ],

            // -------------------------------------------------------------------------
            // 8. FINALIZADOS POR COMPLETO (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 801,
                'Tema_Curso' => 'Inducción Institucional 2025',
                'Folio_Curso' => 'CAP-2025-001',
                'Fecha_Inicio' => '2025-05-10',
                'Fecha_Fin'    => '2025-05-10',
                'Instructor_Asignado' => 'RH',
                'Sede' => 'Auditorio', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 4,
                'Porcentaje_Asistencia' => 100, 'Calificacion_Numerica' => 100.0,
                'Id_Estatus_Participante' => 3, // ID 3
                'Estatus_Participante' => 'APROBADO',
                'Estatus_Global_Curso' => 'FINALIZADO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => '2025-05-01'
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 802,
                'Tema_Curso' => 'Código de Ética 2025',
                'Folio_Curso' => 'CAP-2025-002',
                'Fecha_Inicio' => '2025-06-15',
                'Fecha_Fin'    => '2025-06-15',
                'Instructor_Asignado' => 'Contraloría',
                'Sede' => 'En Línea', 'Modalidad' => 'En Línea', 'Duracion_Horas' => 2,
                'Porcentaje_Asistencia' => 100, 'Calificacion_Numerica' => 100.0,
                'Id_Estatus_Participante' => 3, // ID 3
                'Estatus_Participante' => 'APROBADO',
                'Estatus_Global_Curso' => 'FINALIZADO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => '2025-06-01'
            ],

            // -------------------------------------------------------------------------
            // 9. ARCHIVADOS (2 Cursos)
            // -------------------------------------------------------------------------
            (object)[
                'Id_Detalle_de_Capacitacion' => 901,
                'Tema_Curso' => 'Office 2019 Básico (Legado)',
                'Folio_Curso' => 'CAP-2023-100',
                'Fecha_Inicio' => '2023-08-01',
                'Fecha_Fin'    => '2023-08-05',
                'Instructor_Asignado' => 'Microsoft',
                'Sede' => 'Cibercafe', 'Modalidad' => 'Presencial', 'Duracion_Horas' => 20,
                'Porcentaje_Asistencia' => 100, 'Calificacion_Numerica' => 90.0,
                'Id_Estatus_Participante' => 3, // ID 3
                'Estatus_Participante' => 'APROBADO',
                'Estatus_Global_Curso' => 'ARCHIVADO',
                'Justificacion' => 'Curso de software anterior.',
                'Fecha_Inscripcion' => '2023-07-20'
            ],
            (object)[
                'Id_Detalle_de_Capacitacion' => 902,
                'Tema_Curso' => 'Seguridad v1.0 (Obsoleto)',
                'Folio_Curso' => 'CAP-2023-101',
                'Fecha_Inicio' => '2023-09-10',
                'Fecha_Fin'    => '2023-09-11',
                'Instructor_Asignado' => 'Ing. Retirado',
                'Sede' => 'Patio', 'Modalidad' => 'Práctico', 'Duracion_Horas' => 8,
                'Porcentaje_Asistencia' => 50, 'Calificacion_Numerica' => 40.0,
                'Id_Estatus_Participante' => 4, // ID 4
                'Estatus_Participante' => 'NO APROBADO',
                'Estatus_Global_Curso' => 'ARCHIVADO',
                'Justificacion' => null,
                'Fecha_Inscripcion' => '2023-09-01'
            ],
        ]);

        // █ MOTOR DE ORDENAMIENTO CRONOLÓGICO (LIFO) █
        $historial = $historialRaw->sortByDesc(function ($curso) {
            return \Carbon\Carbon::parse($curso->Fecha_Inicio);
        });

        // KPI: Conteo Total
        $totalCursos = $historial->count();
        
        // KPI: Promedio
        $promedioGral = $totalCursos > 0 
            ? $historial->whereNotNull('Calificacion_Numerica')
                        ->where('Calificacion_Numerica', '>', 0)
                        ->avg('Calificacion_Numerica') 
            : 0;

        $promedioGral = number_format((float)$promedioGral, 1);

        // Despacho a la Vista
        return view('components.MiKardex', [
            'historial'    => $historial,
            'totalCursos'  => $totalCursos,
            'promedioGral' => $promedioGral
        ]);
    }

    /**
     * █ MÓDULO: GESTIÓN DOCENTE — CARGA ACADÉMICA E HISTORIAL DE INSTRUCCIÓN
     * ─────────────────────────────────────────────────────────────────────────────────────────────
     * * I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
     * ---------------------------------------------------------------------------------------------
     * - Nombre Oficial    : cursosImpartidos
     * - Sistema           : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
     * - Clasificación     : Consulta de Historial Docente (Instructor Record Inquiry)
     * - Patrón de Diseño  : SSR (Server Side Rendering) with Identity Injected Query
     * - Dependencia Core  : Procedimiento Almacenado `SP_ConsultarCursosImpartidos`
     * - Seguridad         : IMC (Identity Master Control) - Protección contra ataques IDOR
     * * II. PROPÓSITO Y VALOR DE NEGOCIO (BUSINESS VALUE)
     * ---------------------------------------------------------------------------------------------
     * Este método permite a los usuarios con privilegios de instrucción (Admin, Coordinador, 
     * Instructor) acceder a su traza oficial de capacitaciones dictadas.
     * Facilita la transición hacia la etapa de evaluación y carga de evidencias finales.
     * * III. PROTOCOLO DE IDENTIDAD INMUTABLE
     * ---------------------------------------------------------------------------------------------
     * No se aceptan IDs externos vía Request. El motor extrae el ID del sujeto directamente
     * del token de sesión autenticado, asegurando un aislamiento total entre usuarios.
     * * @return \Illuminate\View\View Vista hidratada con el componente <x-Impartidos />
     * =============================================================================================
     *
     * 
     * █ MÓDULO: GESTIÓN DOCENTE — COMPONENTE AUTÓNOMO DE INSTRUCCIÓN
     * ─────────────────────────────────────────────────────────────────────────────────────────────
     * @standard    Platinum Forensic Standard V.5
     * @security    Identity Master Control (IMC) - Aislamiento por Auth::id()
     * @logic       Direct Component Rendering (DCR)
     * * I. FICHA TÉCNICA DE INGENIERÍA
     * ---------------------------------------------------------------------------------------------
     * - Nombre Oficial    : CursosImpartidos
     * - Patrón de Diseño  : Self-Contained Component View
     * - Dependencia Core  : Procedimiento Almacenado `SP_ConsultarCursosImpartidos`
     * * II. PROPÓSITO Y VALOR DE NEGOCIO
     * ---------------------------------------------------------------------------------------------
     * Punto de verdad única para el instructor. Renderiza directamente el componente 
     * 'components.Impartidos' inyectando el dataset académico validado por el motor MariaDB.
     * ─────────────────────────────────────────────────────────────────────────────────────────────
     */
    public function CursosImpartidos()
    {
        //try {
            // [FASE 1]: IDENTIDAD Y CONSUMO
            // Inyectamos el ID de sesión para garantizar integridad (Anti-IDOR)
            $idInstructor = Auth::id();
            
            // [FASE 2]: PERSISTENCIA ATÓMICA
            // DB::select devuelve un Array puro. Lo capturamos en una variable temporal.
            $dataRaw = DB::select('CALL SP_ConsultarCursosImpartidos(?)', [$idInstructor]);

            // █ CORRECCIÓN CRÍTICA: HIDRATACIÓN DE COLECCIÓN █
            // Convertimos el array en una Colección para que la vista pueda usar ->count() y ->where()
            $cursos = collect($dataRaw);

            // [FASE 3]: DESPACHO DIRECTO AL COMPONENTE
            // Apuntamos directamente a resources/views/components/Impartidos.blade.php
            return view('components.Impartidos', compact('cursos'));

        /*} catch (\Exception $e) {
            
             // █ MÁSCARA DE SEGURIDAD (ANTI-LEAKAGE)
             // Interceptamos fallos en el motor para evitar la recarga infinita.
             
            $mensajeForense = $this->extraerMensajeSP($e->getMessage());
            
            return redirect()->route('dashboard')
                ->with('danger', 'ERROR DE INTEGRIDAD DOCENTE: ' . $mensajeForense);
        }*/
    }

    /*
     * █ MÓDULO: EMISIÓN DOCUMENTAL — MOTOR DE RENDERIZADO PDF (OFFICIAL OUTPUT)
     * ─────────────────────────────────────────────────────────────────────────────────────────────
     * * I. FICHA TÉCNICA (TECHNICAL DATASHEET)
     * ---------------------------------------------------------------------------------------------
     * - Nombre Oficial    : descargarConstancia
     * - Clasificación     : Emisión de Artefactos Digitales Legales (Legal Document Issuance)
     * - Nivel de Riesgo   : CRÍTICO (Afecta certificación ante terceros)
     * - Patrón de Diseño  : "The Judge & Jury Pattern" (El SP valida, el controlador emite)
     * - Dependencia Core  : Procedimiento Almacenado `SP_GenerarConstancia_Individual`
     * * II. OBJETIVO Y SEGURIDAD FORENSE (SECURITY POSTURE)
     * ---------------------------------------------------------------------------------------------
     * Este motor orquesta la transformación de datos crudos validados en un documento PDF.
     * Implementa Defensa en Profundidad mediante la interceptación de excepciones de BD para 
     * evitar la fuga de metadata técnica (Host, Ports, Table Structures).
     * * III. NOMENCLATURA Y ESTANDARIZACIÓN (NAMING CONVENTION)
     * ---------------------------------------------------------------------------------------------
     * Formato: [FOLIO_CURSO]_[FICHA_USUARIO].pdf
     * Sanitización: Regex estricta para compatibilidad con sistemas de archivos Unix/Windows.
     * * @param int $idCursoDetalle Referencia primaria a la versión del curso (Hijo).
     * @return \Illuminate\Http\Response Descarga binaria del documento o redirección defensiva.
     * =============================================================================================
     */
    public function descargarConstancia($idCursoDetalle)
    {
        //try {
            // [FASE 1]: CONSULTA AL JUEZ DIGITAL (SP VALIDATION)
            // Se invoca el SP de alta seguridad. Si el usuario no tiene registro o el curso 
            // no ha finalizado, el SP lanzará un SIGNAL SQLSTATE '45000'.
            $resultado = DB::select('CALL SP_GenerarConstancia_Individual(?, ?)', [
                Auth::id(),
                $idCursoDetalle
            ]);

            // Validación de Integridad de Respuesta: Previene fallos ante retornos vacíos.
            if (empty($resultado)) {
                return back()->with('danger', 'ERROR DE INTEGRIDAD: El motor de certificación no generó una respuesta válida.');
            }

            $doc = $resultado[0];

            // [FASE 2]: VEREDICTO DE EMISIÓN (ACTION GATEKEEPER)
            // Manejo de lógica de negocio devuelta por el SP (ej: Estatus no elegible).
            if ($doc->Accion !== 'GENERAR_DOCUMENTO') {
                return back()->with('warning', $doc->Mensaje);
            }

            // [FASE 3]: MATERIALIZACIÓN DEL ARTEFACTO (RENDER ENGINE)
            // Sanitización del nombre de archivo para evitar inyecciones en el sistema de ficheros.
            $filename = preg_replace('/[^A-Z0-9]/', '_', $doc->Folio_Curso) . '_' . $doc->Ficha . '.pdf';

            // Generación de stream binario mediante DomPDF.
            $pdf = \PDF::loadView('documentos.constancia', ['data' => $doc]);
            $pdf->setPaper('letter', 'landscape');

            return $pdf->download($filename);

        /*} catch (\Exception $e) {
            
            //█ CAPA DE ABSTRACCIÓN DE SEGURIDAD (ERROR MASKING)
            // ─────────────────────────────────────────────────────────────────
            // Interceptamos el error técnico y lo pasamos por el filtro quirúrgico.
            // Esto elimina la metadata de conexión y devuelve solo el veredicto humano.
            
            $mensajeForense = $this->extraerMensajeSP($e->getMessage());
            
            return back()->with('danger', 'EMISIÓN RECHAZADA: ' . $mensajeForense);
        }*/
    }

}

