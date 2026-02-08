/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarCapacitacion
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_RegistrarCapacitacion
   - Tipo: Transacción Atómica Compuesta (Atomic Composite Transaction)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento constituye el **Motor Transaccional de Alta de Cursos** (Core Booking Engine).
   Su responsabilidad es orquestar el nacimiento de un "Expediente de Capacitación" en el sistema.
   
   A diferencia de un alta simple en un catálogo (que afecta una sola tabla), este proceso es una
   operación financiera y operativa crítica que afecta múltiples entidades simultáneamente.
   Debe garantizar que:
     A) Se reserve el presupuesto (vinculación con Gerencia).
     B) Se comprometan los recursos (Instructor y Sede).
     C) Se establezca la identidad legal del evento (Folio Único).
   
   [CRITICIDAD]: EXTREMA. 
   Es el punto de entrada único para toda la operación académica. Si este SP falla o permite datos
   corruptos, todo el módulo de asistencias, calificaciones y reportes DC-3 colapsará en cascada.

   3. ARQUITECTURA DE DEFENSA EN PROFUNDIDAD (DEFENSE IN DEPTH)
   ------------------------------------------------------------
   Este componente no confía ciegamente en el Frontend. Implementa 5 capas de seguridad concéntricas:

   CAPA 1: SANITIZACIÓN DE ENTRADA (INPUT HYGIENE)
      - Objetivo: Eliminar ruido y estandarizar datos antes de procesar.
      - Mecanismo: Aplicación forzosa de funciones `TRIM()` y `NULLIF()`.
      - Justificación: Evita que "   CAP-001  " y "CAP-001" sean tratados como folios distintos.
        Garantiza que una cadena vacía '' se trate como NULL para activar las validaciones de obligatoriedad.

   CAPA 2: VALIDACIÓN SINTÁCTICA Y DE NEGOCIO (FAIL FAST STRATEGY)
      - Objetivo: Rechazar peticiones incoherentes sin consumir ciclos de base de datos costosos.
      - Mecanismo: Bloques `IF` secuenciales que validan reglas aritméticas y lógicas.
      - Reglas Implementadas:
          * [RN-01] Integridad de Identificadores: Rechazo de IDs <= 0 (ej: -1, 0).
          * [RN-02] Rentabilidad Operativa: El `Cupo_Programado` debe ser >= 5. Menos de esto no es rentable.
          * [RN-03] Coherencia Temporal: La `Fecha_Inicio` no puede ser posterior a `Fecha_Fin`.
          * [RN-04] Completitud: Ningún campo obligatorio puede ser NULL.

   CAPA 3: VALIDACIÓN DE INTEGRIDAD REFERENCIAL EXTENDIDA ("ANTI-ZOMBIE RESOURCES")
      - Objetivo: Asegurar la vitalidad de las relaciones.
      - Problema: Un ID puede existir en la tabla foránea (Integridad Referencial Estándar), pero
        el registro puede estar "Borrado Lógicamente" (`Activo = 0`).
      - Solución: Se realizan consultas `SELECT` ligeras en tiempo real ("Just-in-Time") para verificar
        que cada recurso (Gerencia, Tema, Instructor, Sede, Modalidad, Estatus) no solo exista,
        sino que tenga su bandera `Activo = 1`.
      - Resultado: Previene la creación de cursos vinculados a sedes clausuradas o instructores dados de baja.

   CAPA 4: INTEGRIDAD DE IDENTIDAD Y CONCURRENCIA (UNIQUE IDENTITY LOCKING)
      - Objetivo: Garantizar la unicidad absoluta del Folio del Curso.
      - Problema: En un entorno de alta concurrencia, dos coordinadores pueden intentar registrar el 
        mismo folio (ej: 'CAP-2026-A01') en el mismo milisegundo.
      - Solución: Se aplica un **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`) sobre la tabla padre
        antes de intentar la inserción. Esto serializa las operaciones conflictivas.
      - Resultado: El primer usuario obtiene el candado y graba; el segundo recibe un error controlado [409].

   CAPA 5: ATOMICIDAD TRANSACCIONAL (ACID COMPLIANCE)
      - Objetivo: Consistencia total. "Todo o Nada".
      - Problema: Si se inserta la Cabecera (`Capacitaciones`) pero falla la inserción del Detalle
        (`DatosCapacitaciones`) por un error de red o disco, quedaría un registro "huérfano" y corrupto.
      - Solución: Encapsulamiento en `START TRANSACTION` ... `COMMIT`.
      - Mecanismo de Recuperación: Un `EXIT HANDLER` captura cualquier excepción (`SQLEXCEPTION`) y
        ejecuta un `ROLLBACK` automático, dejando la base de datos en su estado original inmaculado.

   4. ESPECIFICACIÓN DE INTERFAZ (CONTRACT SPECIFICATION)
   ------------------------------------------------------
   [ENTRADA - INPUTS]
   Se requieren 11 parámetros estrictamente tipados. No se admiten objetos JSON ni XML; la estructura
   es plana para maximizar el rendimiento del motor SQL.

   [SALIDA - OUTPUTS]
   Retorna un Resultset de fila única (Single Row) con la confirmación de la operación:
      - `Mensaje` (VARCHAR): Texto descriptivo del éxito ("ÉXITO: Capacitación registrada...").
      - `Accion` (VARCHAR): Código de operación ('CREADA') para lógica del Frontend.
      - `Id_Capacitacion` (INT): La llave primaria interna generada (Auto-Increment).
      - `Folio` (VARCHAR): La llave de negocio confirmada.

   [CÓDIGOS DE ERROR - SQLSTATE MAPPING]
   El procedimiento normaliza los errores en códigos estándar HTTP-like para facilitar la integración API:
      - [400] Bad Request: Errores de validación sintáctica (nulos, fechas invertidas, cupo bajo).
      - [409] Conflict: Errores de integridad (Folio duplicado, Instructor inactivo/zombie).
      - [500] Internal Error: Fallos de sistema durante la escritura física.

   ==================================================================================================== */

DELIMITER $$

-- Eliminamos el procedimiento si existe para asegurar una instalación limpia de la nueva versión.
DROP PROCEDURE IF EXISTS `SP_RegistrarCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarCapacitacion`(
    /* --------------------------------------------------------------------------------------------
       SECCIÓN A: TRAZABILIDAD Y AUDITORÍA
       Datos necesarios para cumplir con los requisitos de compliance y bitácora de cambios.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Usuario_Ejecutor INT,         -- [OBLIGATORIO] ID del usuario (Admin/Coord) que ejecuta la acción.
                                         -- Se utilizará para llenar los campos `Created_By`.

    /* --------------------------------------------------------------------------------------------
       SECCIÓN B: DATOS DE CABECERA (TABLA PADRE: Capacitaciones)
       Información administrativa y financiera de alto nivel. Estos datos definen la identidad del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Numero_Capacitacion VARCHAR(50), -- [OBLIGATORIO] Folio Único (Business Key). Ej: 'CAP-2026-001'.
                                         -- No puede repetirse NUNCA en el sistema.
    IN _Id_Gerencia         INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Gerencias_Activos`.
                                         -- Representa el Centro de Costos dueño del presupuesto.
    IN _Id_Tema             INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Temas_Capacitacion`.
                                         -- Define el contenido académico base.
    IN _Cupo_Programado     INT,         -- [OBLIGATORIO] Meta de asistencia (KPI).
                                         -- Sujeto a Regla de Negocio: Mínimo 5 pax.

    /* --------------------------------------------------------------------------------------------
       SECCIÓN C: DATOS DE DETALLE (TABLA HIJA: DatosCapacitaciones)
       Información logística y operativa de la ejecución específica.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Instructor       INT,         -- [OBLIGATORIO] Foreign Key hacia `Usuarios`.
                                         -- Persona responsable de impartir la cátedra.
    IN _Fecha_Inicio        DATE,        -- [OBLIGATORIO] Fecha de arranque del evento.
    IN _Fecha_Fin           DATE,        -- [OBLIGATORIO] Fecha de conclusión del evento.
    IN _Id_Sede             INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Cases_Sedes`.
                                         -- Ubicación física o virtual.
    IN _Id_Modalidad        INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Modalidad_Capacitacion`.
                                         -- Metodología de entrega (Presencial/En Línea/Híbrido).
    IN _Id_Estatus          INT,         -- [OBLIGATORIO] Foreign Key hacia `Cat_Estatus_Capacitacion`.
                                         -- Estado inicial del flujo (ej: 'Programado', 'En Curso').
                                         -- Nota: Se recibe desde el Frontend, validado por el Framework.
    IN _Observaciones       TEXT         -- [OPCIONAL] Notas de bitácora inicial o contexto adicional.
                                         -- Único campo que permite nulidad semántica.
)
THIS_PROC: BEGIN

    /* ============================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Definición de variables locales para el control de flujo, almacenamiento temporal de IDs
       y banderas de estado.
       ============================================================================================ */
    
    /* Identificadores */
    DECLARE v_Id_Capacitacion_Generado INT DEFAULT NULL; -- Almacenará el ID autogenerado de la Cabecera.
    
    /* Variables de Validación */
    DECLARE v_Folio_Existente VARCHAR(50) DEFAULT NULL;  -- Buffer para verificar duplicidad de folios.
    DECLARE v_Es_Activo TINYINT(1);                      -- Semáforo booleano para validación Anti-Zombie.
    
    /* Control de Excepciones */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;                  -- Bandera para capturar errores de Unique Key (1062).

    /* ============================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (SISTEMA DE DEFENSA)
       Configuración de las respuestas automáticas del motor de base de datos ante errores.
       ============================================================================================ */
    
    /* 1.1 HANDLER DE CONCURRENCIA (Race Condition Shield)
       [QUÉ]: Captura el error MySQL 1062 (Duplicate Entry for Key).
       [POR QUÉ]: Es la última línea de defensa si dos transacciones intentan insertar el mismo folio
       en el mismo microsegundo, superando los bloqueos de lectura.
       [ACCIÓN]: No abortar inmediatamente; marcar la bandera v_Dup=1 para manejo controlado. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER DE FALLO CRÍTICO (System Failure Recovery)
       [QUÉ]: Captura cualquier excepción SQL genérica (SQLEXCEPTION).
       [EJEMPLOS]: Pérdida de conexión, disco lleno, violación de FK no controlada, error de sintaxis.
       [ACCIÓN]: Ejecutar ROLLBACK total para deshacer cambios parciales y RESIGNAL (propagar error). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: CAPA DE SANITIZACIÓN Y VALIDACIÓN SINTÁCTICA (FAIL FAST)
       Validación de tipos de datos, nulidad y reglas aritméticas básicas.
       Si algo falla aquí, se aborta ANTES de realizar cualquier lectura costosa a la base de datos.
       ============================================================================================ */
    
    -- 2.0 Limpieza de Strings
    -- Aplicamos TRIM para eliminar espacios accidentales. NULLIF convierte '' en NULL real.
    SET _Numero_Capacitacion = NULLIF(TRIM(_Numero_Capacitacion), '');
    SET _Observaciones       = NULLIF(TRIM(_Observaciones), '');

    -- 2.1 Validación de Obligatoriedad: FOLIO
    IF _Numero_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: El Folio es obligatorio y no puede estar vacío.';
    END IF;

    -- 2.2 Validación de Obligatoriedad: SELECTORES (Dropdowns)
    -- Los IDs deben ser números positivos. Un valor <= 0 indica una selección inválida o "Seleccione...".
    
    IF _Id_Gerencia IS NULL OR _Id_Gerencia <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Gerencia válida.';
    END IF;

    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Tema válido.';
    END IF;

    -- 2.3 Validación de Negocio: RENTABILIDAD (Cupo Mínimo)
    -- Regla de Negocio: No es viable abrir un grupo para menos de 5 personas.
    IF _Cupo_Programado IS NULL OR _Cupo_Programado < 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [400]: El Cupo Programado debe ser mínimo de 5 asistentes.';
    END IF;

    -- 2.4 Validación de Obligatoriedad: INSTRUCTOR
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Instructor válido.';
    END IF;

    -- 2.5 Validación de Negocio: COHERENCIA TEMPORAL (Fechas)
    -- Regla 1: Ambas fechas son obligatorias.
    IF _Fecha_Inicio IS NULL OR _Fecha_Fin IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Las fechas de Inicio y Fin son obligatorias.';
    END IF;

    -- Regla 2: El tiempo es lineal. El inicio no puede ocurrir después del fin.
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: La Fecha de Inicio no puede ser posterior a la Fecha de Fin.';
    END IF;

    -- 2.6 Validación de Obligatoriedad: LOGÍSTICA (Sede, Modalidad, Estatus)
    IF _Id_Sede IS NULL OR _Id_Sede <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Sede válida.';
    END IF;

    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Modalidad válida.';
    END IF;

    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Estatus válido.';
    END IF;

    /* ============================================================================================
       BLOQUE 3: CAPA DE VALIDACIÓN DE EXISTENCIA (ANTI-ZOMBIE RESOURCES)
       Objetivo: Asegurar la Integridad Referencial Operativa.
       Verificamos contra la BD que los IDs proporcionados no solo existan, sino que estén VIVOS (Activo=1).
       ============================================================================================ */

    -- 3.1 Verificación Anti-Zombie: GERENCIA
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = _Id_Gerencia LIMIT 1;
    
    IF v_Es_Activo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [404]: La Gerencia seleccionada no existe en la base de datos.';
    END IF;
    IF v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Gerencia seleccionada está dada de baja (Inactiva).';
    END IF;

    -- 3.2 Verificación Anti-Zombie: TEMA
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Temas_Capacitacion` WHERE `Id_Cat_TemasCap` = _Id_Tema LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Tema seleccionado no existe o está inactivo.';
    END IF;

    -- 3.3 Verificación Anti-Zombie: INSTRUCTOR
    -- Nota: Validamos tanto la existencia del Usuario como la vigencia de su Info Personal.
    SET v_Es_Activo = NULL;
    SELECT U.Activo INTO v_Es_Activo 
    FROM Usuarios U 
    INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal
    WHERE U.Id_Usuario = _Id_Instructor AND I.Activo = 1 
    LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Instructor seleccionado no está activo o su cuenta ha sido suspendida.';
    END IF;

    -- 3.4 Verificación Anti-Zombie: SEDE
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: La Sede seleccionada no existe o está cerrada.';
    END IF;

    -- 3.5 Verificación Anti-Zombie: MODALIDAD
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: La Modalidad seleccionada no es válida o está inactiva.';
    END IF;

    -- 3.6 Verificación Anti-Zombie: ESTATUS
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Estatus seleccionado no es válido o está inactivo.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: TRANSACCIÓN MAESTRA (ATOMICIDAD Y PERSISTENCIA)
       Punto de No Retorno. Si llegamos aquí, los datos son puros, válidos y consistentes.
       Iniciamos la escritura física en disco bajo un bloque transaccional ACID.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 4.1: BLINDAJE DE IDENTIDAD (BLOQUEO PESIMISTA)
       Verificamos la unicidad del Folio usando `FOR UPDATE`.
       Esto bloquea el índice del folio si ya existe, obligando a otras transacciones a esperar.
       Evita condiciones de carrera en la verificación de duplicados.
       -------------------------------------------------------------------------------------------- */
    SELECT `Numero_Capacitacion` INTO v_Folio_Existente
    FROM `Capacitaciones`
    WHERE `Numero_Capacitacion` = _Numero_Capacitacion
    LIMIT 1
    FOR UPDATE;

    IF v_Folio_Existente IS NOT NULL THEN
        ROLLBACK; -- Liberamos el bloqueo inmediatamente antes de salir.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE IDENTIDAD [409]: El FOLIO ingresado YA EXISTE en el sistema. No se permiten duplicados.';
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 4.2: INSERCIÓN DE CABECERA (ENTIDAD PADRE)
       Insertamos los datos administrativos en la tabla `Capacitaciones`.
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `Capacitaciones`
    (
        `Numero_Capacitacion`, 
        `Fk_Id_CatGeren`, 
        `Fk_Id_Cat_TemasCap`,
        `Asistentes_Programados`, 
        `Activo`, 
        `created_at`, 
        `updated_at`,
        `Fk_Id_Usuario_Cap_Created_by` -- Auditoría de creación
    )
    VALUES
    (
        _Numero_Capacitacion, 
        _Id_Gerencia, 
        _Id_Tema,
        _Cupo_Programado, 
        1,      -- Regla: Todo curso nace Activo (Visible).
        NOW(), 
        NOW(),
        _Id_Usuario_Ejecutor
    );

    /* Verificación Inmediata de Concurrencia post-INSERT */
    /* Si el Handler 1062 se disparó durante el insert anterior, abortamos. */
    IF v_Dup = 1 THEN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA [409]: El Folio fue registrado por otro usuario hace un instante. Por favor verifique.'; 
    END IF;
    
    /* CRÍTICO: Captura del ID generado (AUTO_INCREMENT) para vincular al Hijo */
    SET v_Id_Capacitacion_Generado = LAST_INSERT_ID();

    /* --------------------------------------------------------------------------------------------
       PASO 4.3: INSERCIÓN DE DETALLE (ENTIDAD HIJA)
       Insertamos los datos operativos en la tabla `DatosCapacitaciones`.
       Esta tabla maneja la "Instancia" o versión actual del curso (Fechas, Instructor, Estatus).
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `DatosCapacitaciones`
    (
        `Fk_Id_Capacitacion`,   -- Vinculación Foreign Key con el Padre recién creado.
        `Fk_Id_Instructor`,
        `Fecha_Inicio`, 
        `Fecha_Fin`,
        `Fk_Id_CatCases_Sedes`, 
        `Fk_Id_CatModalCap`, 
        `Fk_Id_CatEstCap`,
        `AsistentesReales`, 
        `Observaciones`, 
        `Activo`, 
        `created_at`, 
        `updated_at`,
        `Fk_Id_Usuario_DatosCap_Created_by` -- Auditoría de creación del detalle.
    )
    VALUES
    (
        v_Id_Capacitacion_Generado, 
        _Id_Instructor,
        _Fecha_Inicio, 
        _Fecha_Fin,
        _Id_Sede, 
        _Id_Modalidad, 
        _Id_Estatus, -- Insertamos directamente la elección validada del usuario.
        0,           -- Regla: Asistentes Reales inicia en 0 al crear el curso.
        _Observaciones, 
        1,           -- Regla: Detalle nace Activo.
        NOW(), 
        NOW(),
        _Id_Usuario_Ejecutor
    );

    /* Validación Final de Integridad de la Transacción Compuesta */
    /* Si falló el insert del hijo (ej: FK rota no detectada), revertimos el padre. */
    IF v_Dup = 1 THEN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [500]: Fallo crítico en la creación del detalle operativo. Transacción revertida para mantener consistencia.'; 
    END IF;

    /* ============================================================================================
       BLOQUE 5: COMMIT Y RESPUESTA (FINALIZACIÓN EXITOSA)
       Si llegamos aquí, todo es perfecto. Confirmamos los cambios en disco y notificamos.
       ============================================================================================ */
    COMMIT;

    SELECT 
        'ÉXITO: Capacitación registrada correctamente.' AS Mensaje,
        'CREADA' AS Accion,
        v_Id_Capacitacion_Generado AS Id_Capacitacion, -- ID Interno para uso del Backend.
        _Numero_Capacitacion AS Folio;                 -- ID de Negocio para mostrar al Usuario.

END$$

DELIMITER ;