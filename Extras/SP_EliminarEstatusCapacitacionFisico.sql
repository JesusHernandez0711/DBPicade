/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarEstatusCapacitacionFisico
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Este procedimiento representa el mecanismo de "Eliminación Dura" o "Destrucción Física" para un registro
   del catálogo de Estatus de Capacitación. Su función es ejecutar un comando `DELETE` real en la base de datos,
   borrando la información de manera irreversible.

   [CUÁNDO SE USA (ESCENARIOS DE USO)]:
   Esta operación está reservada exclusivamente para tareas de **Corrección Administrativa Inmediata**.
   Se utiliza cuando un administrador ha creado un registro por error (ej: "ESTATUS_PRUEBA_123" o con un código incorrecto)
   y detecta el error antes de que el registro haya sido utilizado en cualquier operación del sistema.

   [DIFERENCIA CRÍTICA CON BAJA LÓGICA]:
   - Baja Lógica (`SP_CambiarEstatus...`): "Este estatus existió y se usó en el pasado, pero ya no lo queremos ver en listas nuevas".
     Se logra cambiando `Activo = 0`. Mantiene la historia.
   - Baja Física (Este SP): "Este estatus fue un error de dedo, nunca debió existir y nadie lo ha usado".
     Se logra con `DELETE FROM`. Borra la historia.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE RIESGOS Y REGLAS DE BLINDAJE (ZERO TOLERANCE INTEGRITY)
   ----------------------------------------------------------------------------------------------------
   [RN-01] CANDADO DE HISTORIAL ABSOLUTO (HISTORICAL LOCK):
      - Principio: "La historia es sagrada e inmutable".
      - Regla de Negocio: Está estrictamente PROHIBIDO eliminar físicamente un estatus si este ha sido referenciado
        en **CUALQUIER** momento por una capacitación (`DatosCapacitaciones`).
      - Alcance de la Validación: La validación no distingue entre capacitaciones activas o inactivas. Si existe
        un registro de hace 5 años (aunque esté borrado lógicamente) que usó este estatus, la eliminación se bloquea.
      - Justificación Técnica: Si permitimos el borrado, las capacitaciones históricas quedarían con una llave foránea
        rota (`Fk_Id_CatEstCap` apuntando a un ID inexistente), lo que provocaría errores en reportes, auditorías
        o violaciones de integridad referencial a nivel de motor de base de datos (Error 1451).

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (DATABASE SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con nivel de aislamiento serializable para la fila objetivo.
   - ESTRATEGIA DE CONCURRENCIA: Implementación de **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`).
     Esto asegura que mientras el sistema verifica si el registro tiene dependencias, ningún otro usuario
     pueda agregarle una dependencia nueva (Race Condition).
   - MANEJO DE ERRORES: Captura específica de violaciones de integridad referencial (SQLSTATE 1451) como
     segunda línea de defensa.

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarEstatusCapacitacionFisico`$$

CREATE PROCEDURE `SP_EliminarEstatusCapacitacionFisico`(
    IN _Id_Estatus INT -- [OBLIGATORIO] El Identificador Único (PK) del registro que se desea destruir permanentemente.
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DEFINICIÓN DE VARIABLES DE ENTORNO
       Propósito: Inicializar los contenedores temporales necesarios para la lógica de validación.
       ======================================================================================== */
    
    /* Variable de control para verificar si el registro objetivo existe en la base de datos. */
    DECLARE v_Existe INT DEFAULT NULL;
    
    /* Variable para almacenar el nombre del estatus y usarlo en el mensaje de éxito (Feedback de usuario). */
    DECLARE v_Nombre_Estatus VARCHAR(255) DEFAULT NULL;
    
    /* Variable contador para cuantificar el número de veces que este estatus ha sido utilizado en la historia. */
    DECLARE v_Referencias INT DEFAULT 0;

    /* ========================================================================================
       BLOQUE 1: DEFINICIÓN DE HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Establecer protocolos de respuesta ante errores técnicos críticos.
       ======================================================================================== */
    
    /* [1.1] Handler para Error de Llave Foránea (Foreign Key Constraint Fail - 1451)
       Objetivo: Actúa como una red de seguridad final. Si por alguna razón nuestra validación manual (Bloque 4)
       falla o se omite, el motor de base de datos intentará bloquear el DELETE si hay hijos. Este handler
       captura ese error nativo y lo traduce a un mensaje comprensible para el usuario. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Deshace cualquier cambio pendiente.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [1451]: No se puede eliminar el registro porque existen dependencias a nivel de base de datos (FK Constraint) que no fueron detectadas previamente.'; 
    END;

    /* [1.2] Handler Genérico para Excepciones SQL
       Objetivo: Capturar cualquier otro error imprevisto (caída de conexión, disco lleno, error de sintaxis). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Reenvía el error original al servidor de aplicaciones.
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       Propósito: Verificar la integridad de los parámetros de entrada antes de iniciar procesos costosos.
       ======================================================================================== */
    
    /* Validación de Integridad: El ID no puede ser nulo ni menor o igual a cero. */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de Estatus proporcionado es inválido.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Aislar el registro objetivo del resto del sistema para operar con seguridad.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: LECTURA Y BLOQUEO DEL REGISTRO OBJETIVO
       ----------------------------------------------------------------------------------------
       Ejecutamos una consulta para obtener los datos del registro y aplicar un bloqueo de escritura (`FOR UPDATE`).
       
       EFECTO DEL BLOQUEO:
       - La fila correspondiente a `_Id_Estatus` queda "congelada".
       - Nadie puede editar este estatus mientras decidimos si lo borramos.
       - Nadie puede usar este estatus para una nueva capacitación mientras estamos aquí.
       - Nadie puede borrarlo en paralelo. */
    
    SELECT 1, `Nombre` 
    INTO v_Existe, v_Nombre_Estatus
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* Validación de Existencia: Si el SELECT no encontró nada, `v_Existe` será NULL. */
    IF v_Existe IS NULL THEN
        ROLLBACK; -- Liberamos recursos aunque no haya locks efectivos.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus solicitado para eliminación no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: REGLAS DE NEGOCIO (INTEGRIDAD REFERENCIAL MANUAL)
       Propósito: Verificar lógicamente si es seguro proceder con la destrucción.
       ======================================================================================== */

    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE HISTORIAL (EL CANDADO ABSOLUTO)
       ----------------------------------------------------------------------------------------
       Realizamos un conteo en la tabla operativa `DatosCapacitaciones` para ver si este ID
       aparece en la columna `Fk_Id_CatEstCap`.
       
       CRITERIO DE BÚSQUEDA (IMPORTANTE):
       - NO aplicamos ningún filtro de `Activo = 1`.
       - Buscamos en TODO el historial, incluyendo registros que hayan sido dados de baja lógica.
       - Razón: La integridad referencial física de la base de datos no distingue entre registros activos o inactivos.
         Si existe una fila hija apuntando a este padre, el padre no puede morir. */
    
    SELECT COUNT(*) INTO v_Referencias
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_CatEstCap` = _Id_Estatus;

    /* EVALUACIÓN DEL RESULTADO:
       Si `v_Referencias` es mayor a 0, significa que el estatus tiene historia.
       Por lo tanto, la eliminación física está prohibida. */
    IF v_Referencias > 0 THEN
        ROLLBACK; -- Cancelamos la operación de borrado.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar físicamente este Estatus. Existen registros históricos de capacitaciones (activos o inactivos) asociados a él. Para ocultarlo, utilice la opción de DESACTIVACIÓN (Baja Lógica).';
    END IF;

    /* ========================================================================================
       BLOQUE 5: EJECUCIÓN DESTRUCTORA (DELETE)
       Propósito: Realizar el borrado físico una vez superadas todas las validaciones.
       ======================================================================================== */
    
    /* Si el flujo llega a este punto, significa que:
       1. El registro existe.
       2. Está bloqueado para nosotros.
       3. No tiene ninguna dependencia en la tabla de capacitaciones.
       Es seguro proceder con la destrucción. */
       
    DELETE FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA FINAL
       Propósito: Hacer permanentes los cambios y notificar al cliente.
       ======================================================================================== */
    COMMIT; -- Confirmamos la transacción. El registro desaparece permanentemente.

    /* Retornamos un mensaje de éxito incluyendo el nombre del estatus borrado para confirmación visual */
    SELECT CONCAT('ÉXITO: El Estatus "', v_Nombre_Estatus, '" ha sido eliminado permanentemente del sistema.') AS Mensaje,
           'ELIMINADO_FISICO' AS Accion,
           _Id_Estatus AS Id_Estatus;

END$$

DELIMITER ;