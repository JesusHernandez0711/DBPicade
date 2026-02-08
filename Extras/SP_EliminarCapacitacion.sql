/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarCapacitacion (HARD DELETE / BORRADO FÍSICO)
   ====================================================================================================
   
   1. FICHA TÉCNICA DE INGENIERÍA
   ------------------------------
   - Nombre Oficial:      SP_EliminarCapacitacion
   - Clasificación:       Operación Destructiva de Alto Riesgo (High-Risk Destructive Operation).
   - Tipo:                Physical Delete (DELETE FROM...).
   - Nivel de Seguridad:  CRÍTICO (Requiere validación de "Hoja Limpia").

   2. PROPÓSITO Y REGLAS DE NEGOCIO
   --------------------------------
   Este procedimiento elimina PERMANENTEMENTE un expediente de capacitación y todo su historial de versiones
   de la base de datos. A diferencia del "Archivado" (Soft Delete), esto no tiene deshacer.
   
   [REGLA DE INTEGRIDAD ACADÉMICA - "EL ESCUDO DE ALUMNOS"]:
   Es estrictamente PROHIBIDO eliminar un curso si existe al menos un (1) participante vinculado a 
   cualquiera de sus versiones (detalles), ya sean vigentes o históricas.
   
   - Si hay alumnos: Se ABORTA la operación con Error 409 (Conflicto de Dependencia).
     * Razón: Borrar el curso dejaría huérfanos los registros académicos o diplomas de los empleados.
   
   - Si NO hay alumnos: Se procede a la DESTRUCCIÓN EN CASCADA.
     * Paso 1: Eliminar Hijos (DatosCapacitaciones).
     * Paso 2: Eliminar Padre (Capacitaciones).

   3. COMPORTAMIENTO DE SISTEMA
   ----------------------------
   Esta función está diseñada para limpiar errores de captura ("Creé un curso por error y nadie se ha inscrito aún").
   No está diseñada para depurar cursos viejos con historia real.
   ==================================================================================================== */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarCapacitacion`$$

CREATE PROCEDURE `SP_EliminarCapacitacion`(
    IN _Id_Capacitacion INT -- ID del Expediente Padre a destruir.
)
THIS_PROC: BEGIN

    /* --------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES
       -------------------------------------------------------------------------------------------- */
    DECLARE v_Total_Alumnos INT DEFAULT 0; -- Contador de dependencias (Nietos).
    DECLARE v_Folio VARCHAR(50);           -- Para confirmar qué se borró.

    /* --------------------------------------------------------------------------------------------
       HANDLER DE SEGURIDAD
       Si algo falla durante el borrado físico, revertimos para no dejar datos corruptos a medias.
       -------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       FASE 1: VERIFICACIÓN DE EXISTENCIA (PRE-CHECK)
       ============================================================================================ */
    SELECT `Numero_Capacitacion` INTO v_Folio
    FROM `Capacitaciones`
    WHERE `Id_Capacitacion` = _Id_Capacitacion;

    IF v_Folio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El curso que intenta eliminar no existe.';
    END IF;

    /* ============================================================================================
       FASE 2: EL ESCUDO DE INTEGRIDAD (VALIDACIÓN DE DEPENDENCIAS)
       Buscamos si existen "Nietos" (Participantes) vinculados a este "Abuelo" (Capacitación).
       Hacemos un JOIN desde el Padre -> Hijos -> Nietos.
       ============================================================================================ */
    
    SELECT COUNT(*) INTO v_Total_Alumnos
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion;

    /* [PUNTO DE BLOQUEO]: Si el contador es mayor a 0, detenemos todo. */
    IF v_Total_Alumnos > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [409]: Imposible eliminar. Existen participantes/alumnos registrados en este curso (historial académico activo). Debe dar de baja a los alumnos manualmente antes de intentar borrar el curso.';
    END IF;

    /* ============================================================================================
       FASE 3: EJECUCIÓN DE LA DESTRUCCIÓN (CASCADE DELETE)
       Si llegamos aquí, el curso está "limpio" (sin alumnos). Procedemos a borrar.
       ============================================================================================ */
    START TRANSACTION;

    /* 3.1 Eliminar Hijos (Detalles/Versiones) */
    /* Primero borramos las versiones para respetar la integridad referencial (FK) */
    DELETE FROM `DatosCapacitaciones` 
    WHERE `Fk_Id_Capacitacion` = _Id_Capacitacion;

    /* 3.2 Eliminar Padre (Expediente Maestro) */
    DELETE FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = _Id_Capacitacion;

    /* ============================================================================================
       FASE 4: CONFIRMACIÓN
       ============================================================================================ */
    COMMIT;

    SELECT 
        'ELIMINADO' AS `Estado_Final`,
        CONCAT('El expediente ', v_Folio, ' ha sido eliminado permanentemente del sistema.') AS `Mensaje`;

END$$

DELIMITER ;