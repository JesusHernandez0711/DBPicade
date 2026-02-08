/* ============================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_EditarPerfilPropio]
   ============================================================================================
   AUTOR: Arquitectura de Software PICADE
   FECHA: 2026
   VERSIÓN: 2.3 (PLATINUM STANDARD - SELF-SERVICE, IDEMPOTENCY, HYBRID VALIDATION & LOCKING)

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [PROPÓSITO CENTRAL]:
   Orquestar la actualización atómica del "Expediente Digital" del usuario autenticado.
   Sustituye y unifica los flujos de "Completar Perfil" (Onboarding) y "Editar Mi Perfil".

   [PROBLEMA A RESOLVER]:
   En un sistema de alta concurrencia, permitir que el usuario edite sus propios datos presenta
   riesgos de integridad (asignarse a puestos inexistentes) y colisión (dos sesiones editando
   al mismo tiempo).
   
   Este SP actúa como un **Motor Transaccional Blindado** que garantiza:
   1. Consistencia: No se pueden guardar referencias a catálogos borrados o inactivos.
   2. Seguridad: El usuario no puede escalar privilegios ni modificar datos de otros.
   3. Eficiencia: No se toca el disco si no hubo cambios reales.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   --------------------------------------------------------------------------------------------
   [RN-01] VALIDACIÓN HÍBRIDA DE ADSCRIPCIÓN (LAZY & STRICT CHECK):
      - Contexto: La realidad operativa a veces supera a la actualización de catálogos.
      - Regla Estricta: 'Régimen' y 'Región' son OBLIGATORIOS (Datos macro siempre conocidos).
      - Regla Perezosa (Lazy): 'Puesto', 'CT', 'Depto', 'Gerencia' son OPCIONALES (Permiten NULL).
      - Integridad: Si el usuario envía un ID para un campo opcional, se valida estrictamente
        que exista y esté `Activo=1`. No se permiten IDs "zombis".

   [RN-02] PROTECCIÓN DE IDENTIDAD (IDENTITY COLLISION):
      - Se permite corregir la FICHA (error de dedo al registro).
      - Se valida que la nueva ficha no pertenezca a OTRO usuario (`Id != Me`).
      - El Email NO se toca aquí (se delega a un módulo de seguridad con re-autenticación).

   --------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   --------------------------------------------------------------------------------------------
   [BLOQUEO PESIMISTA - PESSIMISTIC LOCKING]:
   - Problema: "Race Condition". El usuario abre su perfil en dos pestañas, edita cosas distintas
     y guarda casi al mismo tiempo. El último "gana" y sobrescribe al primero sin saberlo.
   - Solución: Al inicio de la transacción, ejecutamos `SELECT ... FOR UPDATE`.
   - Efecto: La fila del usuario se "congela". Cualquier otra transacción que intente leerla
     o escribirla deberá esperar a que esta termine. Garantiza aislamiento total (SERIALIZABLE).

   --------------------------------------------------------------------------------------------
   IV. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   --------------------------------------------------------------------------------------------
   [MOTOR DE DETECCIÓN DE CAMBIOS]:
   - Antes de escribir, el SP compara el Snapshot (Valores Actuales) vs Inputs.
   - Usamos el operador `<=>` (Null-Safe Equality) para comparar campos que pueden ser NULL.
   - Si todo es idéntico, retornamos `ACCION: 'SIN_CAMBIOS'` y hacemos COMMIT inmediato.
   - Beneficio: Ahorro masivo de I/O de disco y evita ensuciar los logs de auditoría.

   --------------------------------------------------------------------------------------------
   V. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   --------------------------------------------------------------------------------------------
   Retorna un resultset estructurado para el Frontend:
      - Mensaje (VARCHAR): Feedback granular ("Se actualizó: Foto, Puesto").
      - Accion (VARCHAR): 'ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO'.
      - Id_Usuario (INT): Contexto.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarPerfilPropio`$$

CREATE PROCEDURE `SP_EditarPerfilPropio`(
    /* -----------------------------------------------------------------
       1. CONTEXTO DE SEGURIDAD (AUTH TOKEN)
       Este ID debe venir del Middleware de Autenticación.
       ----------------------------------------------------------------- */
    IN _Id_Usuario_Sesion INT,

    /* -----------------------------------------------------------------
       2. IDENTIDAD DIGITAL & VISUAL
       Datos para la tarjeta de presentación del usuario.
       ----------------------------------------------------------------- */
    IN _Ficha            VARCHAR(50),
    IN _Url_Foto         VARCHAR(255), 

    /* -----------------------------------------------------------------
       3. IDENTIDAD HUMANA (DEMOGRÁFICOS)
       Datos fundamentales para la Huella Humana.
       ----------------------------------------------------------------- */
    IN _Nombre            VARCHAR(255),
    IN _Apellido_Paterno  VARCHAR(255),
    IN _Apellido_Materno  VARCHAR(255),
    IN _Fecha_Nacimiento  DATE,
    IN _Fecha_Ingreso     DATE,

    /* -----------------------------------------------------------------
       4. MATRIZ DE ADSCRIPCIÓN (CATÁLOGOS)
       IDs provenientes de los Dropdowns. Algunos son obligatorios, otros opcionales.
       ----------------------------------------------------------------- */
    IN _Id_Regimen        INT, -- [OBLIGATORIO]
    IN _Id_Puesto         INT, -- [OPCIONAL]
    IN _Id_CentroTrabajo  INT, -- [OPCIONAL]
    IN _Id_Departamento   INT, -- [OPCIONAL]
    IN _Id_Region         INT, -- [OBLIGATORIO]
    IN _Id_Gerencia       INT, -- [OPCIONAL]
    
    /* -----------------------------------------------------------------
       5. METADATOS ADMINISTRATIVOS
       Datos tabulares informativos.
       ----------------------------------------------------------------- */
    IN _Nivel             VARCHAR(50),
    IN _Clasificacion     VARCHAR(100)
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Contenedores en memoria para la lógica de comparación y control de flujo.
       ============================================================================================ */
    
    /* Punteros de Relación y Banderas */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; 
    DECLARE v_Es_Activo       TINYINT(1);       
    DECLARE v_Id_Duplicado    INT;              
    
    /* Variables de Normalización (Input '0' -> NULL BD) */
    DECLARE v_Id_Puesto_Norm  INT;
    DECLARE v_Id_CT_Norm      INT;
    DECLARE v_Id_Dep_Norm     INT;
    DECLARE v_Id_Gerencia_Norm INT;

    /* Variables de Snapshot (Para almacenar el estado "ANTES" de la edición) */
    DECLARE v_Ficha_Act       VARCHAR(50);
    DECLARE v_Foto_Act        VARCHAR(255);
    DECLARE v_Nombre_Act      VARCHAR(255);
    DECLARE v_Paterno_Act     VARCHAR(255);
    DECLARE v_Materno_Act     VARCHAR(255);
    DECLARE v_Nacim_Act       DATE;
    DECLARE v_Ingre_Act       DATE;
    DECLARE v_Regimen_Act     INT;
    DECLARE v_Puesto_Act      INT;
    DECLARE v_CT_Act          INT;
    DECLARE v_Dep_Act         INT;
    DECLARE v_Region_Act      INT;
    DECLARE v_Geren_Act       INT;
    DECLARE v_Nivel_Act       VARCHAR(50);
    DECLARE v_Clasif_Act      VARCHAR(100);

    /* Variable Acumuladora de Cambios (El "Chismoso" para Feedback Granular) */
    DECLARE v_Cambios_Detectados VARCHAR(500) DEFAULT '';

    /* ============================================================================================
       BLOQUE 1: HANDLERS (MECANISMOS DE DEFENSA)
       Propósito: Garantizar una salida limpia y mensajes humanos ante errores técnicos.
       ============================================================================================ */
    
    /* [1.1] Handler 1062: Colisión de Unicidad
       Objetivo: Capturar si otro usuario registró la misma Ficha en el último milisegundo. */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: La Ficha que intentas guardar ya existe.';
    END;

    /* [1.2] Handler 1452: Integridad Referencial Rota (CRÍTICO)
       Objetivo: Atrapa casos donde el ID enviado es válido numéricamente (ej: Puesto 5), 
       pero la fila padre fue borrada físicamente de la BD durante la transacción. 
       Evita que el sistema colapse con un error técnico. */
    DECLARE EXIT HANDLER FOR 1452
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: Uno de los catálogos seleccionados dejó de existir en el sistema.';
    END;

    /* [1.3] Handler Genérico: Fallos de sistema imprevistos */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN (INPUT HYGIENE)
       Propósito: Asegurar consistencia de datos (Mayúsculas, Sin espacios, Nulos correctos).
       ============================================================================================ */
    SET _Ficha            = TRIM(_Ficha);
    /* Limpieza de Foto: Si envían cadena vacía, se guarda NULL */
    SET _Url_Foto         = NULLIF(TRIM(_Url_Foto), '');
    
    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));
    SET _Nivel            = TRIM(UPPER(_Nivel));
    SET _Clasificacion    = TRIM(UPPER(_Clasificacion));

    /* Normalización de IDs Opcionales: El Frontend puede enviar '0' para "Sin Selección". 
       La BD requiere NULL para mantener la integridad referencial y ahorrar espacio. */
    SET v_Id_Puesto_Norm   = NULLIF(_Id_Puesto, 0);
    SET v_Id_CT_Norm       = NULLIF(_Id_CentroTrabajo, 0);
    SET v_Id_Dep_Norm      = NULLIF(_Id_Departamento, 0);
    SET v_Id_Gerencia_Norm = NULLIF(_Id_Gerencia, 0);

    /* ============================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST)
       Propósito: Rechazar peticiones inválidas antes de abrir transacción.
       ============================================================================================ */
    
    /* 3.1 Validación de Sesión */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SEGURIDAD [401]: Sesión no válida.';
    END IF;

    /* 3.2 Regla de Obligatoriedad Híbrida (Solo Régimen y Región son Hard Constraints) */
    IF (_Id_Regimen <= 0 OR _Id_Regimen IS NULL) OR 
       (_Id_Region <= 0 OR _Id_Region IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Régimen y Región son obligatorios.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Asegurar aislamiento total para la lectura y escritura.
       ============================================================================================ */
    START TRANSACTION;

    /* 4.1 Bloqueo y Lectura de USUARIO (Parent Entity)
       Usamos `FOR UPDATE` para adquirir un "Write Lock". Nadie más puede tocar esta fila. */
    SELECT `Fk_Id_InfoPersonal`, `Ficha`, `Foto_Perfil_Url`
    INTO v_Id_InfoPersonal, v_Ficha_Act, v_Foto_Act
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Sesion
    FOR UPDATE;

    IF v_Id_InfoPersonal IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [500]: Perfil de datos personales no encontrado.';
    END IF;

    /* 4.2 Bloqueo y Lectura de INFO_PERSONAL (Child Entity)
       Leemos el estado completo actual para alimentar el motor de detección de cambios. */
    SELECT 
        `Nombre`, `Apellido_Paterno`, `Apellido_Materno`, `Fecha_Nacimiento`, `Fecha_Ingreso`,
        `Fk_Id_CatRegimen`, `Fk_Id_CatPuesto`, `Fk_Id_CatCT`, `Fk_Id_CatDep`, `Fk_Id_CatRegion`, `Fk_Id_CatGeren`,
        `Nivel`, `Clasificacion`
    INTO 
        v_Nombre_Act, v_Paterno_Act, v_Materno_Act, v_Nacim_Act, v_Ingre_Act,
        v_Regimen_Act, v_Puesto_Act, v_CT_Act, v_Dep_Act, v_Region_Act, v_Geren_Act,
        v_Nivel_Act, v_Clasif_Act
    FROM `Info_Personal`
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal
    FOR UPDATE;

    /* ============================================================================================
       BLOQUE 5: MOTOR DE DETECCIÓN DE CAMBIOS (EL "CHISMOSO")
       Propósito: Construir el mensaje de feedback granular.
       Lógica: Comparamos campo por campo usando `<=>` (Null-Safe Equality).
       Si hay diferencias, agregamos una etiqueta legible al acumulador.
       ============================================================================================ */
    
    /* 5.1 Cambios en Identidad Digital */
    IF NOT (v_Ficha_Act <=> _Ficha) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Ficha Corporativa, '); END IF;
    IF NOT (v_Foto_Act <=> _Url_Foto) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Foto de Perfil, '); END IF;

    /* 5.2 Cambios en Datos Personales (Agrupados por semántica) */
    IF NOT (v_Nombre_Act <=> _Nombre) OR NOT (v_Paterno_Act <=> _Apellido_Paterno) OR 
       NOT (v_Materno_Act <=> _Apellido_Materno) OR NOT (v_Nacim_Act <=> _Fecha_Nacimiento) THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Datos Personales, ');
    END IF;

    IF NOT (v_Ingre_Act <=> _Fecha_Ingreso) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Fecha de Ingreso, '); END IF;

    /* 5.3 Cambios Laborales (Adscripción y Ubicación) */
    IF NOT (v_Regimen_Act <=> _Id_Regimen) OR NOT (v_Region_Act <=> _Id_Region) OR
       NOT (v_Puesto_Act <=> v_Id_Puesto_Norm) OR NOT (v_CT_Act <=> v_Id_CT_Norm) OR
       NOT (v_Dep_Act <=> v_Id_Dep_Norm) OR NOT (v_Geren_Act <=> v_Id_Gerencia_Norm) OR
       NOT (v_Nivel_Act <=> _Nivel) OR NOT (v_Clasif_Act <=> _Clasificacion) THEN
       
       SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Datos Laborales/Ubicación, ');
    END IF;

    /* ============================================================================================
       BLOQUE 6: VERIFICACIÓN DE IDEMPOTENCIA
       Propósito: Optimización. Si el acumulador sigue vacío, el usuario guardó sin tocar nada.
       Acción: Retornamos éxito inmediato sin tocar disco.
       ============================================================================================ */
    IF v_Cambios_Detectados = '' THEN
        COMMIT; -- Liberamos locks
        SELECT 'No se detectaron cambios en la información.' AS Mensaje, _Id_Usuario_Sesion AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 7: VALIDACIONES DE NEGOCIO (Solo se ejecutan si hubo cambios reales)
       Propósito: Proteger la integridad de los datos antes de escribir.
       ============================================================================================ */

    /* 7.1 Colisión de Ficha (Solo si cambió la ficha)
       Verificamos que la nueva ficha no pertenezca a OTRO usuario (`Id != Me`). */
    IF LOCATE('Ficha', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Ficha` = _Ficha AND `Id_Usuario` <> _Id_Usuario_Sesion LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: La Ficha ingresada ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.2 Vigencia de Catálogos (Anti-Zombie Check) 
       Verificamos manualmente que los catálogos seleccionados sigan existiendo y estén `Activo=1`.
       Si alguno fue borrado, el Rollback ocurre aquí. */
    
    /* Obligatorios */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Régimen no válido.'; END IF;

    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Región no válida.'; END IF;

    /* Opcionales (Solo validamos si NO son NULL) */
    IF v_Id_Puesto_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = v_Id_Puesto_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Puesto inactivo.'; END IF;
    END IF;

    IF v_Id_CT_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = v_Id_CT_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Centro de Trabajo inactivo.'; END IF;
    END IF;

    IF v_Id_Dep_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Departamentos` WHERE `Id_CatDep` = v_Id_Dep_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Departamento inactivo.'; END IF;
    END IF;

    IF v_Id_Gerencia_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = v_Id_Gerencia_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Gerencia inactiva.'; END IF;
    END IF;

    /* ============================================================================================
       BLOQUE 8: PERSISTENCIA (UPDATE)
       Propósito: Aplicar los cambios en la base de datos de manera atómica.
       ============================================================================================ */
    
    /* 8.1 Actualizar Info Personal */
    UPDATE `Info_Personal`
    SET 
        `Nombre` = _Nombre, `Apellido_Paterno` = _Apellido_Paterno, `Apellido_Materno` = _Apellido_Materno,
        `Fecha_Nacimiento` = _Fecha_Nacimiento, `Fecha_Ingreso` = _Fecha_Ingreso,
        `Fk_Id_CatRegimen` = _Id_Regimen, `Fk_Id_CatPuesto` = v_Id_Puesto_Norm,
        `Fk_Id_CatCT` = v_Id_CT_Norm, `Fk_Id_CatDep` = v_Id_Dep_Norm,
        `Fk_Id_CatRegion` = _Id_Region, `Fk_Id_CatGeren` = v_Id_Gerencia_Norm,
        `Nivel` = _Nivel, `Clasificacion` = _Clasificacion,
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at` = NOW()
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;

    /* 8.2 Actualizar Usuario */
    UPDATE `Usuarios`
    SET
        `Ficha` = _Ficha,
        `Foto_Perfil_Url` = _Url_Foto,
        `Fk_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Sesion;

    /* ============================================================================================
       BLOQUE 9: CONFIRMACIÓN Y RESPUESTA DINÁMICA
       Propósito: Cerrar la transacción y enviar el feedback al usuario.
       ============================================================================================ */
    COMMIT;

    /* Formateamos el mensaje final quitando la última coma sobrante y agregando el prefijo de éxito */
    /* Ejemplo salida: "ÉXITO: Se ha actualizado: Foto de Perfil, Datos Laborales." */
    SELECT 
        CONCAT('ÉXITO: Se ha actualizado: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Sesion AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;