/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarEstatusCapacitacion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO ESTRATÉGICO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este Stored Procedure actúa como el **Constructor de la Máquina de Estados** del sistema PICADE.
   Su responsabilidad es dar de alta los nodos lógicos que definirán el flujo de trabajo de las capacitaciones
   (ej: 'PROGRAMADO' -> 'EN CURSO' -> 'FINALIZADO').

   [EL PROBLEMA DE NEGOCIO (THE BUSINESS RISK)]:
   La integridad de los reportes operativos depende de que no existan estados duplicados, ambiguos o 
   "fantasmas". 
   - Riesgo 1 (Ambigüedad): Tener dos estados 'CANCELADO' y 'ANULADO' confunde a los usuarios y fragmenta la data.
   - Riesgo 2 (Inconsistencia): Un estado 'FINALIZADO' que no tenga la bandera `Es_Final=1` provocaría que 
     los cursos nunca liberen a sus instructores, bloqueando la programación futura.

   [LA SOLUCIÓN: GESTIÓN DE IDENTIDAD UNÍVOCA]:
   Este SP implementa una estrategia de **"Alta Inteligente con Autosanación"**.
   No solo inserta datos; verifica la existencia previa, resuelve conflictos de identidad y recupera 
   registros históricos ("Muertos") para evitar la proliferación de basura en la base de datos.

   ----------------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE BLINDAJE (SECURITY & INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   
   [RN-01] INTEGRIDAD DE DATOS (MANDATORY FIELDS):
      - Principio: "Datos completos o nada".
      - Regla: El `Código` (ID Técnico) y el `Nombre` (ID Humano) son obligatorios.
      - Justificación: Un estatus sin código no puede ser referenciado por el backend. Un estatus sin nombre 
        es invisible para el usuario.
      - Nota: La `Descripción` es opcional (puede ir vacía).

   [RN-02] IDENTIDAD DE DOBLE FACTOR (DUAL IDENTITY CHECK):
      - Principio: "Unicidad Total".
      - Regla: No pueden existir dos estatus con el mismo CÓDIGO (ej: 'FIN'). Tampoco pueden existir dos 
        estatus con el mismo NOMBRE (ej: 'FINALIZADO').
      - Resolución: Se verifica primero el Código (Identificador fuerte) y luego el Nombre. Si hay conflicto 
        cruzado (mismo nombre, diferente código), se aborta para prevenir ambigüedad.

   [RN-03] AUTOSANACIÓN Y RECUPERACIÓN (SELF-HEALING PATTERN):
      - Principio: "Reciclar antes que crear".
      - Regla: Si el estatus que se intenta crear YA EXISTE pero fue eliminado lógicamente (`Activo=0`), 
        el sistema no lanza error. En su lugar, lo "resucita" (Reactiva), actualiza su configuración 
        (`Es_Final`, `Descripción`) y lo devuelve como éxito.

   [RN-04] TOLERANCIA A CONCURRENCIA (RACE CONDITION SHIELD):
      - Principio: "El usuario nunca ve un error técnico".
      - Escenario: Dos administradores intentan crear el mismo estatus al mismo tiempo.
      - Mecanismo: Se implementa el patrón "Re-Resolve". Si el INSERT falla por duplicado (Error 1062), 
        el SP captura el error, revierte la transacción y busca el registro "ganador" para devolverlo 
        como éxito transparente.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (DATABASE SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Aislamiento Serializable (vía Row-Level Locking).
   - ESTRATEGIA DE BLOQUEO: `SELECT ... FOR UPDATE` (Pessimistic Locking).
     * Congela la fila encontrada o el rango de índice durante la validación.
     * Evita lecturas sucias y condiciones de carrera en la verificación de existencia.
   - IDEMPOTENCIA: Si se solicita crear un estatus que ya existe y es idéntico, el sistema retorna éxito 
     sin consumir ciclos de escritura (I/O Optimization).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarEstatusCapacitacion`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos del formulario. Se asume que requieren sanitización.
       ------------------------------------------------------------------------------------------------ */
    IN _Codigo      VARCHAR(50),   -- [OBLIGATORIO] Clave única interna (ej: 'PROG').
    IN _Nombre      VARCHAR(255),  -- [OBLIGATORIO] Nombre descriptivo único (ej: 'PROGRAMADO').
    IN _Descripcion VARCHAR(255),  -- [OPCIONAL] Contexto detallado de uso.
    IN _Es_Final    TINYINT(1)     -- [CRÍTICO] Bandera de lógica de negocio (0=Vivo/Bloqueante, 1=Muerto/Liberador).
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Definición de contenedores para almacenar el estado de la base de datos y diagnósticos.
       ============================================================================================ */
    
    /* Variables de Persistencia (Snapshot del registro en BD) */
    DECLARE v_Id_Estatus INT DEFAULT NULL;       -- Almacena el ID si encontramos el registro.
    DECLARE v_Activo     TINYINT(1) DEFAULT NULL; -- Almacena el estado actual (Activo/Inactivo).
    
    /* Variables para Validación Cruzada (Cross-Check de identidad) */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Semáforo: Controla el flujo lógico cuando ocurren excepciones SQL controladas */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ============================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Asegurar que el procedimiento termine de forma controlada ante cualquier eventualidad.
       ============================================================================================ */
    
    /* 1.1 HANDLER DE COLISIÓN (Error 1062 - Duplicate Entry)
       Objetivo: Capturar colisiones de Unique Key en el INSERT final (nuestra red de seguridad).
       Estrategia: "Graceful Degradation". En lugar de abortar, encendemos la bandera v_Dup
       para activar la rutina de recuperación (Re-Resolve) más adelante. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER CRÍTICO (SQLEXCEPTION)
       Objetivo: Capturar fallos de infraestructura (Disco lleno, Conexión perdida, Error de Sintaxis).
       Estrategia: "Abort & Report". Ante fallos de sistema, revertimos cualquier cambio parcial 
       (ROLLBACK) y propagamos el error original (RESIGNAL) para los logs del backend. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST STRATEGY)
       Propósito: Proteger la base de datos de datos basura antes de abrir transacciones costosas.
       ============================================================================================ */
    
    /* 2.1 NORMALIZACIÓN DE CADENAS
       Eliminamos espacios redundantes (TRIM). NULLIF convierte cadenas vacías '' en NULL reales
       para facilitar la validación booleana estricta. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');
    
    /* Sanitización de Bandera Lógica: Si viene NULL, asumimos FALSE (0 - Bloqueante) por seguridad. */
    SET _Es_Final    = IFNULL(_Es_Final, 0);

    /* 2.2 VALIDACIÓN DE INTEGRIDAD DE CAMPOS OBLIGATORIOS
       Regla: Un Estatus sin Código o Nombre es una entidad corrupta. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO del estatus es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del estatus es obligatorio.';
    END IF;

    /* 2.3 VALIDACIÓN DE DOMINIO (Valores permitidos)
       Regla de Negocio: Es_Final es binario. */
    IF _Es_Final NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo Es_Final solo acepta 0 (Bloqueante) o 1 (Final).';
    END IF;

    /* ============================================================================================
       BLOQUE 3: LÓGICA TRANSACCIONAL PRINCIPAL (CORE BUSINESS LOGIC)
       Propósito: Ejecutar la búsqueda, validación y persistencia de forma atómica.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN PRIMARIA POR CÓDIGO (STRONG ID CHECK)
       Objetivo: Determinar si el identificador técnico ya existe.
       Estrategia: Bloqueo Pesimista (FOR UPDATE) para serializar el acceso a este registro.
       Esto evita que otro admin modifique este registro mientras lo evaluamos.
       -------------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset de seguridad

    SELECT `Id_CatEstCap`, `Nombre`, `Activo` 
    INTO v_Id_Estatus, v_Nombre_Existente, v_Activo
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO A: EL CÓDIGO YA EXISTE EN LA BASE DE DATOS */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* A.1 Validación de Consistencia Semántica
           Regla: Si el código existe, el Nombre asociado debe coincidir con el input.
           Fallo: Si el código es igual pero el nombre diferente, es un conflicto de integridad. */
        IF v_Nombre_Existente <> _Nombre THEN
            ROLLBACK; -- Liberamos el bloqueo antes de lanzar error
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero está asignado a otro nombre.';
        END IF;

        /* A.2 Autosanación (Self-Healing)
           Si el registro existe pero está borrado lógicamente (Activo=0), lo recuperamos.
           NOTA: Se actualizan también la Descripción y la bandera Es_Final con los datos nuevos. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion`
            SET `Activo` = 1,
                /* Lógica de actualización: Si el usuario mandó nueva descripción, la usamos. 
                   Si mandó NULL, conservamos la antigua. */
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`),
                `Es_Final` = _Es_Final, -- Actualización crítica de lógica de negocio
                `updated_at` = NOW()
            WHERE `Id_CatEstCap` = v_Id_Estatus;
            
            COMMIT;
            SELECT 'ÉXITO: Estatus recuperado y actualizado correctamente.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion;
            LEAVE THIS_PROC;
        
        /* A.3 Idempotencia
           Si ya existe y está activo, no duplicamos ni fallamos. Reportamos éxito silente. */
        ELSE
            COMMIT;
            SELECT 'AVISO: El código del estatus ya existe y está activo.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion;
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: VERIFICACIÓN SECUNDARIA POR NOMBRE (WEAK ID CHECK)
       Objetivo: Si el Código es nuevo, asegurarnos que el NOMBRE no esté ocupado por otro código.
       Esto previene duplicados semánticos (ej: dos estatus 'CANCELADO' con códigos distintos).
       -------------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset

    SELECT `Id_CatEstCap`, `Codigo`, `Activo`
    INTO v_Id_Estatus, v_Codigo_Existente, v_Activo
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* B.1 Detección de Conflicto Cruzado
           El nombre existe, pero tiene un código diferente al que intentamos registrar. */
        IF v_Codigo_Existente <> _Codigo THEN
             ROLLBACK;
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ya existe asociado a otro CÓDIGO diferente.';
        END IF;

        /* B.2 Data Enrichment (Caso Legacy)
           Si el registro existía con Código NULL (datos viejos), le asignamos el nuevo código. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Estatus_Capacitacion` SET `Codigo` = _Codigo, `updated_at` = NOW() WHERE `Id_CatEstCap` = v_Id_Estatus;
        END IF;

        /* B.3 Autosanación por Nombre
           Si estaba inactivo, lo reactivamos y actualizamos su configuración lógica. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion` 
            SET `Activo` = 1, 
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`),
                `Es_Final` = _Es_Final,
                `updated_at` = NOW() 
            WHERE `Id_CatEstCap` = v_Id_Estatus;
            
            COMMIT;
            SELECT 'ÉXITO: Estatus reactivado (encontrado por Nombre).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion;
            LEAVE THIS_PROC;
        END IF;

        /* B.4 Idempotencia por Nombre */
        COMMIT;
        SELECT 'AVISO: El estatus ya existe y está activo.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA FÍSICA (INSERT)
       Si llegamos aquí, no hay colisiones conocidas. Procedemos a insertar.
       Aquí existe un riesgo infinitesimal de "Race Condition" si otro usuario inserta en este preciso instante.
       -------------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciar bandera de error
    
    INSERT INTO `Cat_Estatus_Capacitacion`
    (
        `Codigo`, 
        `Nombre`, 
        `Descripcion`, 
        `Es_Final`, 
        `Activo`,
        `created_at`,
        `updated_at`
    )
    VALUES
    (
        _Codigo, 
        _Nombre, 
        _Descripcion, 
        _Es_Final,
        1,      -- Default: Activo
        NOW(),  -- Timestamp Creación
        NOW()   -- Timestamp Actualización
    );

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT fue limpio. */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'ÉXITO: Estatus registrado correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Estatus, 'CREADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 4: SUBRUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar elegantemente el Error 1062 (Duplicate Key) si ocurre una condición de carrera.
       ============================================================================================ */
    
    /* Si estamos aquí, v_Dup = 1. Significa que "perdimos" la carrera contra otro INSERT concurrente. */
    
    ROLLBACK; -- 1. Revertir la transacción fallida para liberar bloqueos parciales.
    
    START TRANSACTION; -- 2. Iniciar una nueva transacción limpia.
    
    SET v_Id_Estatus = NULL;
    
    /* 3. Buscar el registro "ganador" (El que insertó el otro usuario) */
    SELECT `Id_CatEstCap`, `Activo`, `Nombre`
    INTO v_Id_Estatus, v_Activo, v_Nombre_Existente
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Estatus IS NOT NULL THEN
        /* Validación de Seguridad Post-Recuperación */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Concurrencia detectada con conflicto de datos.';
        END IF;

        /* Reactivar si el ganador estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion` 
            SET `Activo` = 1, `Es_Final` = _Es_Final, `updated_at` = NOW() 
            WHERE `Id_CatEstCap` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado (tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
        
        /* Retornar el ID existente */
        COMMIT; 
        SELECT 'AVISO: Estatus ya existente (reusado tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* Fallo Irrecuperable (Corrupción de índices o error fantasma) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable.';

END$$

DELIMITER ;