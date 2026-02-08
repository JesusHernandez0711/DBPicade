DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Automata_CicloVida`$$

CREATE PROCEDURE `SP_Automata_CicloVida`()
BEGIN
    /* ════════════════════════════════════════════════════════════════════════════════════════
       MÓDULO DE AUTOMATIZACIÓN DE CICLO DE VIDA (TIME-BASED STATE MACHINE)
       ════════════════════════════════════════════════════════════════════════════════════════
       REGLA 1: DE "EVALUACIÓN" A "FINALIZADO"
       Condición: Han pasado más de 21 días (3 semanas) desde la Fecha Fin.
       Acción: Cambiar Estatus a 4 (Finalizado).
       ════════════════════════════════════════════════════════════════════════════════════════ */
    
    UPDATE DatosCapacitaciones
    SET 
        Fk_Id_CatEstCap = 4, -- FINALIZADO
        updated_at = NOW(),
        Observaciones = CONCAT(Observaciones, ' | [AUTO] Finalizado por término de periodo (3 sem).')
    WHERE 
        Activo = 1 
        AND Fk_Id_CatEstCap IN (3, 5) -- Solo si está 'En Curso' o 'En Evaluación'
        AND DATEDIFF(NOW(), Fecha_Fin) >= 21; -- 3 Semanas de antigüedad

    /* ════════════════════════════════════════════════════════════════════════════════════════
       REGLA 2: DE "FINALIZADO" A "ARCHIVADO"
       Condición: Han pasado más de 60 días (2 meses) DESDE QUE FINALIZÓ.
       Cálculo: Fecha Fin + 21 días (Finalizado) + 60 días (Espera) = 81 días totales.
       Acción: Cambiar Activo a 0 (Archivado).
       ════════════════════════════════════════════════════════════════════════════════════════ */

    UPDATE DatosCapacitaciones
    SET 
        Activo = 0, -- ARCHIVADO (Soft Delete)
        updated_at = NOW()
    WHERE 
        Activo = 1
        AND Fk_Id_CatEstCap = 4 -- Solo si ya estaba 'Finalizado'
        AND DATEDIFF(NOW(), Fecha_Fin) >= 81; -- 21 días + 60 días = 81 días totales desde el fin real

    /* Feedback en consola para pruebas manuales */
    SELECT 'Autómata ejecutado: Ciclos de vida actualizados.' AS Mensaje;

END$$

DELIMITER ;

DELIMITER $$

DROP EVENT IF EXISTS `EVT_Diario_CicloVida`$$

CREATE EVENT `EVT_Diario_CicloVida`
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 3 HOUR) -- Empieza mañana a las 3 AM
DO
BEGIN
    CALL `SP_Automata_CicloVida`();
END$$

DELIMITER ;

