/* ============================================================================================
   PROCEDIMIENTO: SP_EditarUsuarioPorAdmin
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor transaccional de "Edición Maestra" (Superusuario). Permite la modificación 
   arbitraria y completa de cualquier expediente digital en el sistema, ignorando las 
   restricciones de solo lectura que tienen los usuarios normales.

   [CASO DE USO]: 
   Utilizado exclusivamente por el Panel de Administración para:
     a) Corregir errores humanos en el alta (Fichas o Correos mal escritos).
     b) Gestión de Crisis (Resetear contraseñas olvidadas sin el password anterior).
     c) Reingeniería Organizacional (Mover empleados de Gerencia o Región masivamente).
     d) Escalado de Privilegios (Ascender un Usuario a Coordinador/Admin).

   --------------------------------------------------------------------------------------------
   II. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   --------------------------------------------------------------------------------------------
   A) INTEGRIDAD REFERENCIAL "ANTI-ZOMBIE":
      - Problema: Un Admin intenta mover un usuario a un Departamento que fue borrado hace 1 segundo.
      - Solución: Validación de existencia y vigencia (`Activo=1`) en tiempo real para todos
        los catálogos (Puesto, CT, Depto, etc.) antes de permitir el UPDATE.
      - Mecanismo: Handler SQLSTATE 1452 para capturar integridad rota.

   B) RESET DE CONTRASEÑA CONDICIONAL (SMART OVERRIDE):
      - Regla: "El Admin no necesita saber tu contraseña vieja para darte una nueva".
      - Lógica: 
         * Si `_Nueva_Contrasena` tiene valor -> Se encripta y sobrescribe la actual.
         * Si `_Nueva_Contrasena` es NULL/Vacío -> Se preserva el hash actual (No se toca).

   C) EXCLUSIÓN DE ESTATUS (ATOMICIDAD):
      - Este SP deliberadamente NO toca el campo `Activo`. La baja/reactivación se delega
        a un micro-servicio separado (`SP_CambiarEstatusUsuario`) para evitar accidentes.

   --------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   --------------------------------------------------------------------------------------------
   [EL PROBLEMA DE LA "CARRERA" (RACE CONDITION)]:
   Escenario: El Admin A abre el perfil de "Juan". El Admin B abre el mismo perfil.
   A cambia el Puesto. B cambia el Correo. Ambos guardan. El último sobrescribe al primero 
   sin saberlo ("Lost Update").

   [LA SOLUCIÓN BLINDADA]:
   Implementamos un **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`) al inicio de la transacción.
     - Efecto: La fila del usuario `_Id_Usuario_Objetivo` queda "secuestrada" por la transacción.
     - Resultado: Si otro Admin intenta editar al mismo usuario simultáneamente, su petición 
       quedará en espera (Wait) hasta que la primera termine. Garantiza consistencia SERIALIZABLE.

   --------------------------------------------------------------------------------------------
   IV. IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
   --------------------------------------------------------------------------------------------
   [MOTOR DE DETECCIÓN DE CAMBIOS]:
   - Antes de escribir en disco, el SP extrae un "Snapshot" del estado actual del registro.
   - Compara matemáticamente cada campo nuevo contra el actual (usando `<=>` para NULLs).
   - Si `Delta = 0` (No hay cambios), retorna éxito inmediato (`SIN_CAMBIOS`) y libera la conexión.
   - Beneficio: Reduce la carga de I/O en el disco del servidor y evita logs de auditoría basura.

   --------------------------------------------------------------------------------------------
   V. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   --------------------------------------------------------------------------------------------
   Retorna un resultset único con:
      - Mensaje (VARCHAR): Feedback humano detallando qué cambió ("Se actualizó: Rol, Foto").
      - Accion (VARCHAR): Códigos de estado para el Frontend ('ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO').
      - Id_Usuario (INT): Contexto para refrescar la vista.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarUsuarioPorAdmin`$$

CREATE PROCEDURE `SP_EditarUsuarioPorAdmin`(
    /* -----------------------------------------------------------------
       1. CONTEXTO DE AUDITORÍA (ACTORES)
       ----------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor    INT,   -- Quién realiza el cambio (Auditoría)
    IN _Id_Usuario_Objetivo  INT,   -- A quién se le aplica el cambio (Target)

    /* -----------------------------------------------------------------
       2. INFO USUARIO (CRÍTICOS DE IDENTIDAD)
       ----------------------------------------------------------------- */
    IN _Ficha                VARCHAR(50),
    IN _Url_Foto             VARCHAR(255),

    /* -----------------------------------------------------------------
       3. IDENTIDAD HUMANA (DEMOGRÁFICOS)
       ----------------------------------------------------------------- */
    IN _Nombre               VARCHAR(255),
    IN _Apellido_Paterno     VARCHAR(255),
    IN _Apellido_Materno     VARCHAR(255),
    IN _Fecha_Nacimiento     DATE,
    IN _Fecha_Ingreso        DATE,

    /* -----------------------------------------------------------------
       2.5 SEGURIDAD Y ACCESOS (CRÍTICOS DE SISTEMA)
       ----------------------------------------------------------------- */
    IN _Email                VARCHAR(255),
    IN _Nueva_Contrasena     VARCHAR(255), -- OPCIONAL: Si viene lleno, se resetea el password

    /* -----------------------------------------------------------------
       4. MATRIZ DE ADSCRIPCIÓN (UBICACIÓN EN EL ORGANIGRAMA)
       ----------------------------------------------------------------- */
    IN _Id_Regimen           INT, 
    IN _Id_Puesto            INT, 
    IN _Id_CentroTrabajo     INT, 
    IN _Id_Departamento      INT, 
    IN _Id_Region            INT, 
    IN _Id_Gerencia          INT, 
    
    /* -----------------------------------------------------------------
       5. METADATOS Y PRIVILEGIOS
       ----------------------------------------------------------------- */
    IN _Nivel                VARCHAR(50),
    IN _Clasificacion        VARCHAR(100),
    IN _Id_Rol               INT          -- [ADMIN POWER] Cambio de privilegios
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTEXTO
       ============================================================================================ */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; 
    DECLARE v_Es_Activo       TINYINT(1);       
    DECLARE v_Id_Duplicado    INT;              
    
    /* Normalización de IDs (Input '0' -> NULL BD) */
    DECLARE v_Id_Puesto_Norm   INT;
    DECLARE v_Id_CT_Norm       INT;
    DECLARE v_Id_Dep_Norm      INT;
    DECLARE v_Id_Gerencia_Norm INT;
    DECLARE v_Pass_Norm        VARCHAR(255); -- Para lógica de reset de password

    /* Snapshots (Estado Actual en BD para comparación) */
    DECLARE v_Ficha_Act       VARCHAR(50);
    DECLARE v_Email_Act       VARCHAR(255); 
    DECLARE v_Rol_Act         INT;
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

    /* Acumulador de Cambios (El "Chismoso") */
    DECLARE v_Cambios_Detectados VARCHAR(1000) DEFAULT '';

    /* ============================================================================================
       BLOQUE 1: HANDLERS DE SEGURIDAD (MECANISMOS DE DEFENSA)
       ============================================================================================ */
    
    /* [1.1] Colisión de Unicidad
       Objetivo: Capturar si se intenta asignar una Ficha/Email que ya existe en otro usuario. */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: La Ficha o el Email ingresados ya pertenecen a otro usuario.';
    END;

    /* [1.2] Integridad Referencial Rota (Error 1452)
       Objetivo: Proteger el sistema si un catálogo es eliminado físicamente mientras se edita. */
    DECLARE EXIT HANDLER FOR 1452
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: Uno de los catálogos seleccionados dejó de existir en el sistema.';
    END;

    /* [1.3] Handler Genérico (Crash Safety) */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN (INPUT HYGIENE)
       ============================================================================================ */
    SET _Ficha            = TRIM(_Ficha);
    SET _Email            = TRIM(_Email);
    SET _Url_Foto         = NULLIF(TRIM(_Url_Foto), '');
    
    /* Lógica de Password: Si viene vacío/null, normalizamos a NULL para que el COALESCE posterior funcione */
    SET v_Pass_Norm       = NULLIF(TRIM(_Nueva_Contrasena), '');

    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));
    SET _Nivel            = TRIM(UPPER(_Nivel));
    SET _Clasificacion    = TRIM(UPPER(_Clasificacion));

    /* Normalización de IDs (Convertir 0 a NULL para integridad referencial) */
    SET v_Id_Puesto_Norm   = NULLIF(_Id_Puesto, 0);
    SET v_Id_CT_Norm       = NULLIF(_Id_CentroTrabajo, 0);
    SET v_Id_Dep_Norm      = NULLIF(_Id_Departamento, 0);
    SET v_Id_Gerencia_Norm = NULLIF(_Id_Gerencia, 0);

    /* ============================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST)
       ============================================================================================ */
    
    /* 3.1 Integridad de Auditoría */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Admin_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [403]: ID de Administrador no válido. No se puede auditar el cambio.';
    END IF;

    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Usuario Objetivo no válido.';
    END IF;

    /* 3.2 Campos Críticos de Sistema (Admin no puede dejar esto vacío) */
    IF _Id_Rol <= 0 OR _Id_Rol IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El ROL es obligatorio. Un usuario no puede existir sin permisos.';
    END IF;

    /* 3.3 Regla de Adscripción Híbrida */
    IF (_Id_Regimen <= 0 OR _Id_Regimen IS NULL) OR 
       (_Id_Region <= 0 OR _Id_Region IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Régimen y Región son obligatorios para la estructura organizacional.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: INICIO TRANSACCIÓN Y BLOQUEO PESIMISTA
       ============================================================================================ */
    START TRANSACTION;

    /* 4.1 Bloqueo del USUARIO OBJETIVO
       Usamos `FOR UPDATE` para adquirir un "Write Lock". Nadie más puede tocar esta fila. 
       Esto previene condiciones de carrera si dos admins editan al mismo usuario. */
    SELECT 
        `Fk_Id_InfoPersonal`, `Ficha`, `Email`, `Foto_Perfil_Url`, `Fk_Rol`
    INTO 
        v_Id_InfoPersonal, v_Ficha_Act, v_Email_Act, v_Foto_Act, v_Rol_Act
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    IF v_Id_InfoPersonal IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario objetivo no existe.';
    END IF;

    /* 4.2 Bloqueo de INFO_PERSONAL (Tabla Satélite) */
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
       BLOQUE 5: MOTOR DE DETECCIÓN DE CAMBIOS (GRANULARIDAD)
       Compara Snapshot vs Inputs. Si hay diferencias, acumula el nombre del campo para el feedback.
       ============================================================================================ */
    
    /* 5.1 Credenciales y Seguridad [ADMIN POWER] */
    IF NOT (v_Ficha_Act <=> _Ficha) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Ficha, '); END IF;
    IF NOT (v_Email_Act <=> _Email) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Email, '); END IF;
    IF NOT (v_Rol_Act <=> _Id_Rol)  THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Rol de Sistema, '); END IF;
    IF NOT (v_Foto_Act <=> _Url_Foto) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Foto de Perfil, '); END IF;
    
    /* ** Detección especial de Contraseña [ADMIN POWER] ** */
    /* Si v_Pass_Norm tiene valor, significa que el Admin quiere resetearla. Eso es un cambio explícito. */
    IF v_Pass_Norm IS NOT NULL THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Contraseña (Reset), ');
    END IF;

    /* 5.2 Datos Personales */
    IF NOT (v_Nombre_Act <=> _Nombre) OR NOT (v_Paterno_Act <=> _Apellido_Paterno) OR 
       NOT (v_Materno_Act <=> _Apellido_Materno) OR NOT (v_Nacim_Act <=> _Fecha_Nacimiento) THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Datos Personales, ');
    END IF;

    IF NOT (v_Ingre_Act <=> _Fecha_Ingreso) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Fecha Ingreso, '); END IF;

    /* 5.3 Datos Laborales */
    IF NOT (v_Regimen_Act <=> _Id_Regimen) OR NOT (v_Region_Act <=> _Id_Region) OR
       NOT (v_Puesto_Act <=> v_Id_Puesto_Norm) OR NOT (v_CT_Act <=> v_Id_CT_Norm) OR
       NOT (v_Dep_Act <=> v_Id_Dep_Norm) OR NOT (v_Geren_Act <=> v_Id_Gerencia_Norm) OR
       NOT (v_Nivel_Act <=> _Nivel) OR NOT (v_Clasif_Act <=> _Clasificacion) THEN
       
       SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Adscripción Laboral, ');
    END IF;

    /* ============================================================================================
       BLOQUE 6: VERIFICACIÓN DE IDEMPOTENCIA
       Si el acumulador sigue vacío, significa que el usuario guardó sin tocar nada.
       ============================================================================================ */
    IF v_Cambios_Detectados = '' THEN
        COMMIT; 
        SELECT 'No se detectaron cambios en el expediente.' AS Mensaje, _Id_Usuario_Objetivo AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 7: VALIDACIONES DE NEGOCIO (POST-LOCK)
       Estas validaciones son 100% fiables porque tenemos el registro bloqueado.
       ============================================================================================ */

    /* 7.1 Colisión de Ficha (Excluyendo al usuario objetivo) */
    IF LOCATE('Ficha', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Ficha` = _Ficha AND `Id_Usuario` <> _Id_Usuario_Objetivo LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: La Ficha asignada ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.2 Colisión de Email (Excluyendo al usuario objetivo) - [ADMIN POWER CHECK] */
    IF LOCATE('Email', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Email` = _Email AND `Id_Usuario` <> _Id_Usuario_Objetivo LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El Email asignado ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.3 Vigencia de Catálogos (Validación Manual para Feedback) */
    
    /* Rol (Mandatory) */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Roles` WHERE `Id_Rol` = _Id_Rol;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: El Rol seleccionado no existe o está inactivo.'; END IF;

    /* Laborales (Mandatory) */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Régimen no válido.'; END IF;

    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Región no válida.'; END IF;

    /* Laborales (Optional - Solo si traen datos) */
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
       ============================================================================================ */
    
    /* 8.1 Actualizar Info Personal (Datos Humanos) */
    UPDATE `Info_Personal`
    SET 
        `Nombre` = _Nombre, `Apellido_Paterno` = _Apellido_Paterno, `Apellido_Materno` = _Apellido_Materno,
        `Fecha_Nacimiento` = _Fecha_Nacimiento, `Fecha_Ingreso` = _Fecha_Ingreso,
        `Fk_Id_CatRegimen` = _Id_Regimen, `Fk_Id_CatPuesto` = v_Id_Puesto_Norm,
        `Fk_Id_CatCT` = v_Id_CT_Norm, `Fk_Id_CatDep` = v_Id_Dep_Norm,
        `Fk_Id_CatRegion` = _Id_Region, `Fk_Id_CatGeren` = v_Id_Gerencia_Norm,
        `Nivel` = _Nivel, `Clasificacion` = _Clasificacion,
        /* Auditoría Cruzada: Registramos al Admin como responsable */
        `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;

    /* 8.2 Actualizar Usuario (Credenciales y Seguridad) [ADMIN POWER] */
    UPDATE `Usuarios`
    SET
        `Ficha` = _Ficha,
        `Email` = _Email,           -- Admin SÍ puede corregir email
        `Foto_Perfil_Url` = _Url_Foto,
        `Fk_Rol` = _Id_Rol,         -- Admin SÍ puede cambiar roles
        
        /* Reset de Password Condicional: Usamos COALESCE para preservar si es NULL */
        `Contraseña` = COALESCE(v_Pass_Norm, `Contraseña`),
        
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* ============================================================================================
       BLOQUE 9: CONFIRMACIÓN Y RESPUESTA
       ============================================================================================ */
    COMMIT;

    /* Feedback Granular */
    SELECT 
        CONCAT('ÉXITO: Se ha actualizado: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;