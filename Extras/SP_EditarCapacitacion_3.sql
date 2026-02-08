/* ====================================================================================================
   PROCEDIMIENTO: SP_EditarCapacitacion
   ====================================================================================================
   
   SECCIÓN 1: FICHA TÉCNICA DEL ARTEFACTO (ARTIFACT DATASHEET)
   ----------------------------------------------------------------------------------------------------
   - Nombre Lógico:      Motor de Versionado y Edición Forense de Cursos
   - Tipo:               Stored Procedure Transaccional (ACID Compliant)
   - Nivel de Aislamiento: SERIALIZABLE (Implícito por bloqueos de escritura en InnoDB)
   - Estrategia de Persistencia: "Append-Only Ledger with State Relinking"
     (Libro mayor de solo agregación con re-enlace de estado)

   SECCIÓN 2: MAPEO DE DEPENDENCIAS (DEPENDENCY MAPPING)
   ----------------------------------------------------------------------------------------------------
   - Dependencias de Entrada (Tablas Padre):
     * DatosCapacitaciones (Versión Anterior)
     * Capacitaciones (Expediente Maestro)
     * Usuarios (Editor, Instructor)
     * Catálogos (Sedes, Modalidad, Estatus)
   - Dependencias de Salida (Tablas Afectadas):
     * DatosCapacitaciones (INSERT nueva versión, UPDATE vieja versión)
     * Capacitaciones (UPDATE timestamp)
     * Capacitaciones_Participantes (UPDATE masivo de punteros FK)

   SECCIÓN 3: ESPECIFICACIÓN DE LA LÓGICA DE NEGOCIO (BUSINESS LOGIC SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento implementa el principio de "Inmutabilidad Histórica".
   Al editar un curso, NO se sobrescriben los datos existentes. Se genera una nueva "hoja" en la historia.
   
   [CICLO DE VIDA DE LA EDICIÓN]:
   1. Validación Forense: Se verifica que la versión a editar sea la VIGENTE (Activo=1).
      Si alguien más editó hace 1 segundo, la operación se rechaza (Optimistic Locking).
   2. Versionado (Branching): Se crea un nuevo registro en `DatosCapacitaciones` con los cambios.
   3. Archivado (Soft Delete): La versión anterior pasa a `Activo=0`.
   4. Re-enlace (Relinking): En lugar de clonar datos (lo que duplicaría registros innecesariamente),
      se mueven los punteros de los alumnos inscritos para que apunten a la nueva versión.
      Esto garantiza integridad referencial y optimización de espacio.

   SECCIÓN 4: CÓDIGOS DE RETORNO Y MANEJO DE ERRORES (RETURN CODES)
   ----------------------------------------------------------------------------------------------------
   - EXITOSO: Retorna el ID de la nueva versión y un mensaje con la cantidad de alumnos movidos.
   - ERROR 404: La versión origen no existe.
   - ERROR 409 (Conflicto): La versión origen ya no es vigente (Race Condition) o recursos inactivos.
   - ERROR 400 (Bad Request): Fechas inválidas o falta de justificación.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarCapacitacion`$$

CREATE PROCEDURE `SP_EditarCapacitacion`(
    /* --------------------------------------------------------------------------------------------
       [GRUPO 0]: CONTEXTO TÉCNICO Y DE AUDITORÍA
       Datos invisibles para el usuario pero vitales para la integridad del sistema.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Version_Anterior INT,       -- Puntero a la versión que se está visualizando/editando (Origen).
    IN _Id_Usuario_Editor   INT,       -- ID del usuario que firma legalmente este cambio.

    /* --------------------------------------------------------------------------------------------
       [GRUPO 1]: CONFIGURACIÓN OPERATIVA (MUTABLES ESTRUCTURALES)
       Datos que definen la "Forma" del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Instructor       INT,       -- Nuevo Recurso Humano responsable.
    IN _Id_Sede             INT,       -- Nueva Ubicación física/virtual.
    IN _Id_Modalidad        INT,       -- Nuevo Formato de entrega.
    IN _Id_Estatus          INT,       -- Nuevo Estado del flujo (ej: De 'Programado' a 'Reprogramado').

    /* --------------------------------------------------------------------------------------------
       [GRUPO 2]: DATOS DE EJECUCIÓN (MUTABLES TEMPORALES)
       Datos que definen el "Tiempo y Razón" del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Fecha_Inicio        DATE,      -- Nueva fecha de arranque.
    IN _Fecha_Fin           DATE,      -- Nueva fecha de cierre.
    
    /* --------------------------------------------------------------------------------------------
       [GRUPO 3]: RESULTADOS (MÉTRICAS)
       Datos cuantitativos post-operativos.
       -------------------------------------------------------------------------------------------- */
    IN _Asistentes_Reales   INT,       -- Ajuste manual del conteo de asistencia (si aplica).
    IN _Observaciones       TEXT       -- [CRÍTICO]: Justificación forense del cambio. Es OBLIGATORIA.
)
THIS_PROC: BEGIN

    /* --------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Contenedores temporales para mantener el estado durante la transacción.
       -------------------------------------------------------------------------------------------- */
    DECLARE v_Id_Padre INT;            -- Almacena el ID del Expediente Maestro (Invariable).
    DECLARE v_Nuevo_Id INT;            -- Almacenará el ID generado para la nueva versión.
    DECLARE v_Es_Activo TINYINT(1);    -- Semáforo booleano para validaciones Anti-Zombie.
    DECLARE v_Version_Es_Vigente TINYINT(1); -- Bandera de estado de la versión origen.
    
    -- [AUDITORÍA]: Variable para capturar el conteo real de alumnos movidos antes del COMMIT.
    DECLARE v_Total_Movidos INT DEFAULT 0;

    /* --------------------------------------------------------------------------------------------
       HANDLER DE SEGURIDAD (FAIL-SAFE MECHANISM)
       En caso de cualquier error técnico (disco lleno, desconexión, FK rota), se ejecuta
       un ROLLBACK total para dejar la base de datos en su estado original inmaculado.
       -------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 0: SANITIZACIÓN Y VALIDACIONES LÓGICAS (PRE-FLIGHT CHECK)
       Objetivo: Validar la coherencia de los datos antes de tocar la estructura.
       ============================================================================================ */
    
    /* 0.1 Limpieza de Strings */
    -- QUÉ: Elimina espacios en blanco y convierte cadenas vacías en NULL.
    -- PARA QUÉ: Evitar guardar basura o espacios invisibles en la base de datos.
    SET _Observaciones = NULLIF(TRIM(_Observaciones), '');

    /* 0.2 Validación Temporal (Time Integrity) */
    -- QUÉ: Verifica que la fecha de inicio sea menor o igual a la de fin.
    -- POR QUÉ: El tiempo es lineal. Un evento no puede terminar antes de empezar.
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Fechas inválidas. La fecha de inicio es posterior a la fecha de fin.';
    END IF;

    /* 0.3 Validación de Justificación (Forensic Compliance) */
    -- QUÉ: Exige que el campo Observaciones tenga contenido.
    -- POR QUÉ: En un sistema auditado, no se permite alterar la historia sin documentar la razón ("Why").
    IF _Observaciones IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [400]: La justificación (Observaciones) es obligatoria para realizar un cambio de versión.';
    END IF;

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE INTEGRIDAD ESTRUCTURAL (EL BLINDAJE)
       Objetivo: Evitar la corrupción del árbol genealógico del curso (Relación Padre-Hijo).
       ============================================================================================ */

    /* 1.1 Descubrimiento del Contexto (Parent & State Discovery) */
    -- QUÉ: Busca quién es el padre y en qué estado está la versión que queremos editar.
    -- CÓMO: Consulta directa por ID Primario (Index Look-up).
    SELECT `Fk_Id_Capacitacion`, `Activo` 
    INTO v_Id_Padre, v_Version_Es_Vigente
    FROM `DatosCapacitaciones` 
    WHERE `Id_DatosCap` = _Id_Version_Anterior 
    LIMIT 1;

    /* 1.2 Verificación de Existencia (404 Handling) */
    -- QUÉ: Valida si la consulta anterior encontró algo.
    -- PARA QUÉ: Evitar errores de referencia nula más adelante.
    IF v_Id_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La versión que intenta editar no existe en los registros.';
    END IF;

    /* 1.3 Verificación de Vigencia (Concurrency Protection) */
    -- QUÉ: Verifica que la versión sea la "Cabeza de Rama" actual (Activo=1).
    -- POR QUÉ: Previene condiciones de carrera (Race Conditions). Si dos usuarios editan al mismo tiempo,
    -- el primero gana y el segundo recibe este error para evitar crear ramas paralelas (bifurcaciones).
    IF v_Version_Es_Vigente = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: La versión que intenta editar YA NO ES VIGENTE. Alguien más modificó este curso recientemente.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: VALIDACIÓN DE RECURSOS (ANTI-ZOMBIE RESOURCES CHECK)
       Objetivo: Asegurar que no se asignen recursos dados de baja.
       ============================================================================================ */
    
    /* 2.1 Verificación de Instructor */
    -- QUÉ: Valida que el Instructor exista y esté activo en la tabla de Usuarios e InfoPersonal.
    SELECT I.Activo INTO v_Es_Activo 
    FROM Usuarios U 
    INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal 
    WHERE U.Id_Usuario = _Id_Instructor LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Instructor seleccionado está inactivo o ha sido dado de baja.'; 
    END IF;

    /* 2.2 Verificación de Sede */
    -- QUÉ: Valida el catálogo de Sedes.
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Sede seleccionada está clausurada o inactiva.'; 
    END IF;

    /* 2.3 Verificación de Modalidad */
    -- QUÉ: Valida el catálogo de Modalidades.
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Modalidad seleccionada no es válida actualmente.'; 
    END IF;

    /* 2.4 Verificación de Estatus */
    -- QUÉ: Valida el catálogo de Estatus.
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Estatus seleccionado está obsoleto o inactivo.'; 
    END IF;

    /* ============================================================================================
       BLOQUE 3: TRANSACCIÓN MAESTRA (ATOMIC WRITING)
       Punto de No Retorno. Iniciamos la escritura física en disco.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 3.1: CREACIÓN DE LA NUEVA VERSIÓN (VERSIONING)
       Insertamos la nueva realidad operativa (`DatosCapacitaciones`) vinculada al mismo Padre.
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `DatosCapacitaciones` (
        `Fk_Id_Capacitacion`, `Fk_Id_Instructor`, `Fk_Id_CatCases_Sedes`, `Fk_Id_CatModalCap`, 
        `Fk_Id_CatEstCap`, `Fecha_Inicio`, `Fecha_Fin`, `Observaciones`, `AsistentesReales`, 
        `Activo`, `Fk_Id_Usuario_DatosCap_Created_by`, `created_at`, `updated_at`
    ) VALUES (
        v_Id_Padre, 
        _Id_Instructor, 
        _Id_Sede, 
        _Id_Modalidad, 
        _Id_Estatus, 
        _Fecha_Inicio, 
        _Fecha_Fin, 
        _Observaciones, 
        IFNULL(_Asistentes_Reales, 0), 
        1,                                           -- [REGLA]: La nueva versión nace VIVA (Vigente).
        _Id_Usuario_Editor,  
        NOW(), 
        NOW()
    );

    /* Captura crítica del ID generado para la migración de hijos */
    -- QUÉ: Obtenemos el ID autogenerado (Auto-Increment) de la inserción anterior.
    -- PARA QUÉ: Para usarlo como Foreign Key al mover a los participantes.
    SET v_Nuevo_Id = LAST_INSERT_ID();

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: ARCHIVADO DE LA VERSIÓN ANTERIOR (HISTORICAL ARCHIVING)
       Marcamos la versión origen como "Histórica" (Activo=0).
       Esto garantiza que siempre exista UNA SOLA versión vigente por curso.
       -------------------------------------------------------------------------------------------- */
    UPDATE `DatosCapacitaciones` 
    SET `Activo` = 0 
    WHERE `Id_DatosCap` = _Id_Version_Anterior;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: ACTUALIZACIÓN DE HUELLA EN EL PADRE (GLOBAL AUDIT TRAIL)
       El expediente maestro (`Capacitaciones`) debe saber que fue modificado hoy.
       - Updated_by: Se actualiza al editor actual.
       - Created_by: SE RESPETA INTACTO (Autor Intelectual original).
       -------------------------------------------------------------------------------------------- */
    UPDATE `Capacitaciones`
    SET 
        `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Editor,
        `updated_at` = NOW()
    WHERE `Id_Capacitacion` = v_Id_Padre;

    /* ============================================================================================
       BLOQUE 4: MIGRACIÓN DE NIETOS (ESTRATEGIA: ATOMIC RELINKING 🚀)
       Objetivo: Preservar la integridad de los participantes y su historial académico.
       
       [CAMBIO DE PARADIGMA]: ATOMIC RELINKING
       Anteriormente se usaba "Clonación" (INSERT SELECT). Ahora se usa "Re-enlace" (UPDATE).
       - Se actualiza el puntero `Fk_Id_DatosCap` de todos los alumnos inscritos en la versión anterior.
       - Los alumnos viajan a la nueva versión conservando sus calificaciones e historial.
       - Se evita la duplicidad de registros (Zero-Duplication Policy), manteniendo la base de datos ligera.
       ============================================================================================ */
    
    -- QUÉ: Ejecuta un UPDATE masivo sobre la tabla de participantes.
    -- CÓMO: Busca todos los registros que apuntaban a la versión vieja (`_Id_Version_Anterior`)
    --       y los redirige a la nueva versión (`v_Nuevo_Id`).
    -- CUÁNDO: Dentro de la misma transacción, asegurando consistencia atómica.
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Fk_Id_DatosCap` = v_Nuevo_Id,           -- Apuntamos a la NUEVA versión
        `updated_at` = NOW(),                    -- Registramos el momento del movimiento
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Editor -- Registramos quién autorizó el cambio
    WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior;

    -- [AUDITORÍA]: Capturamos el conteo exacto de afectados ANTES del Commit.
    -- POR QUÉ: Porque el COMMIT resetea el contador ROW_COUNT a 0. Necesitamos esta evidencia.
    SET v_Total_Movidos = ROW_COUNT();

    /* ============================================================================================
       BLOQUE 5: COMMIT Y CONFIRMACIÓN
       Si llegamos aquí, la operación fue atómica y exitosa.
       ============================================================================================ */
    -- QUÉ: Escribe permanentemente los cambios en disco.
    COMMIT;
    
    /* Retorno de resultados para el Frontend */
    -- QUÉ: Devuelve un Result Set con metadata de la operación.
    -- PARA QUÉ: Para que la interfaz de usuario sepa qué pasó y pueda mostrar una notificación.
    SELECT 
        v_Nuevo_Id AS `New_Id_Detalle`,
        'EXITO'    AS `Status_Message`,
        CONCAT('Versión actualizada exitosamente. Se movieron ', v_Total_Movidos, ' expedientes de alumnos a la nueva versión (Sin duplicados).') AS `Feedback`;

END$$

DELIMITER ;