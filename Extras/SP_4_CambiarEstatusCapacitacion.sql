/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacion
   ====================================================================================================
   
   ==========================================================================================================
      I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)                                                   
   ---------------------------------------------------------------------------------------------------------- 
      Nombre Oficial        : SP_CambiarEstatusCapacitacion                                                  
      Alias Operativo       : "El Interruptor Maestro" / "The Lifecycle Toggle Switch"                       
      Versión               : 2.1.0 (Platinum Forensic Edition)                                              
      Fecha de Creación     : 2025-01-22                                                                     
      Autor                 : Arquitectura de Datos PICADE                                                   
      Clasificación         : Transacción de Gobernanza de Ciclo de Vida                                     
                              (Lifecycle Governance Transaction)                                             
      Patrón de Diseño      : "Explicit Toggle Switch with State Validation & Audit Injection"               
      Criticidad            : ALTA (Afecta la visibilidad global del expediente en todo el sistema)          
      Nivel de Aislamiento  : SERIALIZABLE (Implícito por el manejo de transacciones atómicas)               
      Complejidad           : Media-Alta (Validación Jerárquica + Inyección de Texto Forense)                
   
   ==========================================================================================================
      II. PROPÓSITO FORENSE Y DE NEGOCIO (BUSINESS VALUE PROPOSITION)                                        
   ----------------------------------------------------------------------------------------------------------
                                                                                                             
      Este procedimiento actúa como el "Mecanismo de Control de Disponibilidad" del expediente.              
      Su función NO es eliminar datos (DELETE físico está prohibido en la arquitectura), sino                
      controlar la disponibilidad lógica mediante el patrón Soft Delete/Restore.                             
                                                                                                             
      [ANALOGÍA OPERATIVA]:                                                                                  
      Imagina un archivo físico en un sótano. Este SP es el encargado de:                                    
        - ARCHIVAR (0): Mover el expediente del escritorio "ACTIVO" a la caja "HISTÓRICA" en el sótano.      
        - RESTAURAR (1): Sacar el expediente del sótano y regresarlo al escritorio "ACTIVO".                 
      En ningún caso se tritura el papel; solo se cambia su ubicación y visibilidad.                         
                                                                                                             
      [CAMBIO DE PARADIGMA UX]:                                                                              
      A diferencia de un "switch" simple, este procedimiento requiere INTENCIÓN EXPLÍCITA (`_Nuevo_Estatus`).
      Esto elimina la ambigüedad de operaciones accidentales.                                                
                                                                                                             
   ==========================================================================================================
      III. REGLAS DE ORO DEL ARCHIVADO - GOVERNANCE RULES                                                    
   ----------------------------------------------------------------------------------------------------------

      A. PRINCIPIO DE FINALIZACIÓN (COMPLETION PRINCIPLE)                                                    
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: No se permite archivar un curso que está "Vivo" (operativamente activo).                   
                                                                                                             
         [MECANISMO]: El sistema verifica la bandera `Es_Final` del catálogo de estatus.                     
                      Solo los estatus con `Es_Final = 1` son archivables.                                   
                                                                                                             
         [JUSTIFICACIÓN DE NEGOCIO]:                                                                         
         Archivar un curso "PROGRAMADO" o "EN CURSO" lo haría desaparecer del Dashboard Operativo,           
         generando "Cursos Fantasma" (existen, consumen recursos, pero nadie los ve).                        
                                                                                                             
      B. PRINCIPIO DE CASCADA (CASCADE PRINCIPLE)                                                            
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: La acción de Archivar/Restaurar es atómica y jerárquica.                                   
                                                                                                             
         [MECANISMO]: Al modificar el estado del Padre (`Capacitaciones`), se debe                           
                      modificar SIMULTÁNEAMENTE el estado del Hijo vigente (`DatosCapacitaciones`).          
                                                                                                             
         [RAZÓN TÉCNICA]:                                                                                    
         Las vistas del sistema (`Vista_Capacitaciones`) utilizan INNER JOIN. Si padre e hijo                
         tienen banderas `Activo` discrepantes, se rompe la integridad visual.                               
                                                                                                             
      C. PRINCIPIO DE TRAZABILIDAD AUTOMÁTICA (AUDIT INJECTION STRATEGY)                                     
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: Cada acción de archivado debe dejar una huella indeleble en el registro.                   
                                                                                                             
         [MECANISMO]: Al archivar, el sistema inyecta automáticamente una "Nota Forense"                     
                      en el campo `Observaciones` del detalle operativo.                                     
                                                                                                             
         [OBJETIVO]: Que cualquier auditor futuro pueda determinar QUÉ, QUIÉN, CUÁNDO y POR QUÉ.             
                                                                                                             
      D. PRINCIPIO DE IDEMPOTENCIA (IDEMPOTENCY GUARANTEE)                                                   
      ───────────────────────────────────────────────────────────────────────────────────────────────  
         [REGLA]: Ejecutar la misma operación múltiples veces produce el mismo resultado sin efectos         
                  secundarios acumulativos.                                                                  
                                                                                                             
         [MECANISMO]: Si el estado deseado es igual al estado actual, se retorna éxito inmediato             
                      sin tocar el disco duro (ahorro de I/O y preservación de `updated_at`).                
                                                                                                             
   ========================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacion`(
    /* ===============================================================================================
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT PARAMETERS SECTION)
       ===============================================================================================
       Definimos el contrato de interfaz. La tipificación estricta es la primera línea de defensa.
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 1: _Id_Capacitacion
       -----------------------------------------------------------------------------------------------
       [TIPO]          : INT (Entero 32-bit)
       [OBLIGATORIEDAD]: REQUERIDO (NOT NULL, > 0)
       [DESCRIPCIÓN]   : Identificador único (PK) del Expediente Maestro en tabla `Capacitaciones`.
       [ROL]           : Target de la operación.
       ----------------------------------------------------------------------------------------------- */
    IN _Id_Capacitacion     INT,
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 2: _Id_Usuario_Ejecutor
       -----------------------------------------------------------------------------------------------
       [TIPO]          : INT (Entero 32-bit)
       [OBLIGATORIEDAD]: REQUERIDO (NOT NULL, > 0)
       [DESCRIPCIÓN]   : Identificador del usuario (PK) que solicita el cambio.
       [ROL]           : Auditoría. Este ID quedará estampado en los metadatos `Updated_By`.
       ----------------------------------------------------------------------------------------------- */
    IN _Id_Usuario_Ejecutor INT,
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 3: _Nuevo_Estatus
       -----------------------------------------------------------------------------------------------
       [TIPO]          : TINYINT (Entero 8-bit, usado como Booleano/Enum)
       [OBLIGATORIEDAD]: REQUERIDO (NOT NULL, IN (0, 1))
       [DESCRIPCIÓN]   : Bandera explícita de intención.
       [VALORES]       : 
          0 = ARCHIVAR (Soft Delete).
          1 = RESTAURAR (Recovery).
       [ROL]           : Control de Flujo. Determina qué rama lógica se ejecutará.
       ----------------------------------------------------------------------------------------------- */
    IN _Nuevo_Estatus       TINYINT
)
/* ===================================================================================================
   ETIQUETA DE PROCEDIMIENTO (PROCEDURE LABEL)
   Permite el uso de `LEAVE THIS_PROC` para salidas limpias y anticipadas (Early Exit).
   =================================================================================================== */
THIS_PROC: BEGIN

    /* ===============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO (ENVIRONMENT VARIABLES)
       ===============================================================================================
       Propósito: Definir los contenedores de memoria para el procesamiento lógico.
       MySQL exige que todas las declaraciones ocurran antes de cualquier instrucción ejecutable.
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       GRUPO A: VARIABLES DE ESTADO (SNAPSHOT VARIABLES)
       Almacenan la "fotografía" del registro antes de ser modificado.
       ----------------------------------------------------------------------------------------------- */
    DECLARE v_Estado_Actual_Padre TINYINT(1); -- Estado `Activo` actual del Padre.
    
    /* -----------------------------------------------------------------------------------------------
       GRUPO B: VARIABLES DE CONTEXTO HIJO (CHILD CONTEXT)
       Punteros necesarios para realizar la actualización en cascada.
       ----------------------------------------------------------------------------------------------- */
    DECLARE v_Id_Ultimo_Detalle INT;          -- PK del registro `DatosCapacitaciones` vigente.
    
    /* -----------------------------------------------------------------------------------------------
       GRUPO C: VARIABLES DE REGLAS DE NEGOCIO (GOVERNANCE FLAGS)
       Datos extraídos de catálogos para validar si la operación es legal.
       ----------------------------------------------------------------------------------------------- */
    DECLARE v_Es_Estatus_Final TINYINT(1);    -- Bandera crítica: 1=Permite Archivar, 0=Bloquea.
    DECLARE v_Nombre_Estatus VARCHAR(50);     -- Nombre legible para mensajes de error (UX).
    
    /* -----------------------------------------------------------------------------------------------
       GRUPO D: VARIABLES DE AUDITORÍA (FORENSIC DATA)
       Componentes para construir la nota del sistema.
       ----------------------------------------------------------------------------------------------- */
    DECLARE v_Folio VARCHAR(50);              -- Ej: "CAP-2026-001"
    DECLARE v_Clave_Gerencia VARCHAR(50);     -- Ej: "GER-SISTEMAS"
    DECLARE v_Mensaje_Auditoria TEXT;         -- El texto final inyectado.

    /* ===============================================================================================
       BLOQUE 1: HANDLER DE EXCEPCIONES (FAIL-SAFE MECHANISM)
       ===============================================================================================
       Propósito: Garantizar la integridad ACID. Si algo explota, nada se guarda.
       =============================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        /* 1. Deshacer cambios pendientes */
        ROLLBACK; 
        
        /* 2. Propagar el error al stack superior (Backend) */
        RESIGNAL; 
    END;

    /* ===============================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN DE ENTRADA (FAIL FAST STRATEGY)
       ===============================================================================================
       Propósito: Rechazar peticiones mal formadas antes de consumir ciclos de CPU o I/O de disco.
       =============================================================================================== */
    
    /* [2.1] Validación de Identidad del Target */
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Capacitación es inválido o nulo.';
    END IF;

    /* [2.2] Validación de Identidad del Auditor */
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Usuario Ejecutor es obligatorio para la auditoría.';
    END IF;

    /* [2.3] Validación de Dominio Estricta */
    IF _Nuevo_Estatus IS NULL OR _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo "Nuevo Estatus" es obligatorio y solo acepta valores binarios: 0 (Archivar) o 1 (Restaurar).';
    END IF;

    /* ===============================================================================================
       BLOQUE 3: DIAGNÓSTICO Y RECUPERACIÓN DE CONTEXTO (PRE-FLIGHT CHECK)
       ===============================================================================================
       Propósito: Obtener una "Radiografía" del expediente antes de operarlo.
       Estrategia: Single-Query Optimization (JOIN) para minimizar round-trips.
       =============================================================================================== */
    
    /* Consulta 3.1: Obtención de metadatos del Padre */
    SELECT 
        `Cap`.`Activo`,              -- Estado actual (para Idempotencia)
        `Cap`.`Numero_Capacitacion`, -- Para Auditoría
        `Ger`.`Clave`                -- Para Auditoría
    INTO 
        v_Estado_Actual_Padre, 
        v_Folio,
        v_Clave_Gerencia
    FROM `Capacitaciones` `Cap`
    /* JOIN Obligatorio: Integridad Referencial */
    INNER JOIN `Cat_Gerencias_Activos` `Ger` ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    WHERE `Cap`.`Id_Capacitacion` = _Id_Capacitacion 
    LIMIT 1;

    /* Validación 3.2: Verificación de Existencia (404 Handling) */
    IF v_Estado_Actual_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Capacitación solicitada no existe en el catálogo maestro.';
    END IF;

    /* ===============================================================================================
       BLOQUE 4: VERIFICACIÓN DE IDEMPOTENCIA (RESOURCE OPTIMIZATION)
       ===============================================================================================
       Lógica: "Si ya está encendido, no lo enciendas de nuevo".
       Beneficio: Ahorro de escritura en disco y preservación de timestamps.
       =============================================================================================== */
    IF v_Estado_Actual_Padre = _Nuevo_Estatus THEN
        /* Retorno informativo benigno */
        SELECT CONCAT('AVISO: La Capacitación "', v_Folio, '" ya se encuentra en el estado solicitado (', IF(_Nuevo_Estatus=1,'ACTIVO','ARCHIVADO'), ').') AS Mensaje, 
               'SIN_CAMBIOS' AS Accion;
        /* Salida Inmediata */
        LEAVE THIS_PROC;
    END IF;

    /* ===============================================================================================
       BLOQUE 5: ANÁLISIS DE ESTADO OPERATIVO (HIJO VIGENTE)
       ===============================================================================================
       Propósito: Obtener los datos de la última versión del curso para validar reglas de negocio.
       Estrategia: Ordenamiento Descendente + LIMIT 1 para obtener el registro "Head".
       =============================================================================================== */
    SELECT 
        `DC`.`Id_DatosCap`, 
        `CatEst`.`Es_Final`,  -- Bandera de Seguridad (The Kill Switch Guard)
        `CatEst`.`Nombre`     -- Nombre legible para error
    INTO 
        v_Id_Ultimo_Detalle, 
        v_Es_Estatus_Final,
        v_Nombre_Estatus
    FROM `DatosCapacitaciones` `DC`
    INNER JOIN `Cat_Estatus_Capacitacion` `CatEst` ON `DC`.`Fk_Id_CatEstCap` = `CatEst`.`Id_CatEstCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion
    ORDER BY `DC`.`Id_DatosCap` DESC 
    LIMIT 1;

    /* ===============================================================================================
       BLOQUE 6: MOTOR DE DECISIÓN LÓGICA (CORE LOGIC & TRANSACTION)
       ===============================================================================================
       Aquí inicia la fase de escritura. Se abre la transacción ACID.
       =============================================================================================== */
    START TRANSACTION;

    /* -----------------------------------------------------------------------------------------------
       RAMA A: FLUJO DE ARCHIVADO (SOFT DELETE)
       Condición: _Nuevo_Estatus = 0
       ----------------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 0 THEN
        
        /* [PASO 6.A.1]: VALIDACIÓN DE REGLAS DE NEGOCIO (SAFETY LOCK)
           Regla: Solo se permite archivar si `Es_Final = 1`. 
           Si el curso está vivo (0), es ilegal archivarlo. */
        IF v_Es_Estatus_Final = 0 OR v_Es_Estatus_Final IS NULL THEN
            ROLLBACK; -- Abortar transacción
            
            SET @ErrorMsg = CONCAT(
                'ACCIÓN DENEGADA [409]: No se puede archivar un curso activo. ',
                'El estatus actual es "', v_Nombre_Estatus, '", el cual se considera OPERATIVO (No Final). ',
                'Debe finalizar o cancelar la capacitación antes de archivarla.'
            );
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrorMsg;
        END IF;

        /* [PASO 6.A.2]: CONSTRUCCIÓN DE EVIDENCIA FORENSE (AUDIT NOTE)
           Generamos el texto inmutable que quedará en el historial. */
        SET v_Mensaje_Auditoria = CONCAT(
            ' [SISTEMA]: La capacitación con folio ', v_Folio, 
            ' de la Gerencia ', v_Clave_Gerencia, 
            ', fue archivada el ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
            ' porque alcanzó el fin de su ciclo de vida.'
        );

        /* [PASO 6.A.3]: EJECUCIÓN DEL APAGADO EN CASCADA (CASCADE UPDATE) */
        
        /* 1. Apagado del Padre (Expediente) */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 0, 
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW()
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* 2. Apagado del Hijo (Versión) + INYECCIÓN DE NOTA */
        /* Usamos CONCAT_WS para agregar la nota de forma segura (maneja NULLs). */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 0, 
            `Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW(),
            `Observaciones` = CONCAT_WS('\n\n', `Observaciones`, v_Mensaje_Auditoria)
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* [PASO 6.A.4]: CONFIRMACIÓN Y RESPUESTA */
        COMMIT;
        SELECT 'ARCHIVADO' AS `Nuevo_Estado`, 'Expediente archivado y nota de auditoría registrada.' AS `Mensaje`, 'ESTATUS_CAMBIADO' AS Accion;

    /* -----------------------------------------------------------------------------------------------
       RAMA B: FLUJO DE RESTAURACIÓN (UNDELETE)
       Condición: _Nuevo_Estatus = 1
       ----------------------------------------------------------------------------------------------- */
    ELSE
        /* [PASO 6.B.1]: EJECUCIÓN DE RESTAURACIÓN (ADMIN OVERRIDE)
           En restauración, no validamos reglas de negocio complejas. 
           Si el admin quiere restaurarlo, se permite. */
        
        /* 1. Encendido del Padre */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 1, 
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW()
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* 2. Encendido del Hijo */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 1, 
            `Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW()
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* [PASO 6.B.2]: CONFIRMACIÓN Y RESPUESTA */
        COMMIT;
        SELECT 'RESTAURADO' AS `Nuevo_Estado`, 'Expediente restaurado exitosamente.' AS `Mensaje`, 'ESTATUS_CAMBIADO' AS Accion;

    END IF;

END$$

DELIMITER ;