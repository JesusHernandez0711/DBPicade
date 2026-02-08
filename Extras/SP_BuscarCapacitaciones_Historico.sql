USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_BuscarCapacitaciones_Historico
   ====================================================================================================
   
   1. OBJETIVO DE NEGOCIO
   ----------------------
   Alimentar el "Panel de Reportes e Histórico". 
   A diferencia del Grid Principal, este SP es permisivo: busca en TODO el archivo muerto, 
   cursos finalizados, cancelados e incluso eliminados (Soft Deleted), siempre y cuando
   cumplan con los filtros de búsqueda.

   2. PARÁMETROS DE FILTRADO (BÚSQUEDA AVANZADA)
   ---------------------------------------------
   - _Anio (INT): Año de la Fecha de Inicio. (Obligatorio o 0 para todos).
   - _Id_Gerencia (INT): Filtrar por área dueña. (Opcional/NULL).
   - _Texto_Busqueda (VARCHAR): Búsqueda difusa en Folio, Tema o Instructor.

   3. LÓGICA DE INTEGRIDAD (ELIMINACIÓN DE CANDADOS)
   -------------------------------------------------
   - SE ELIMINA el filtro `Capacitaciones.Activo = 1`.
     Razón: Queremos ver cursos que fueron "Archivados" o dados de baja.
   
   - SE MANTIENE el filtro `Vista.Estatus_del_Registro = 1`.
     Razón Técnica: Incluso en el historial, solo nos interesa ver la "Versión Definitiva" 
     de cada curso, no sus borradores intermedios.

   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_BuscarCapacitaciones_Historico`$$

CREATE PROCEDURE `SP_BuscarCapacitaciones_Historico`(
    IN _Anio INT,              -- Ej: 2019
    IN _Id_Gerencia INT,       -- Ej: 5 (O NULL para 'Todas')
    IN _Texto_Busqueda VARCHAR(100) -- Ej: 'EXCEL' (O NULL)
)
BEGIN
    SELECT 
        /* Identificadores para entrar al detalle */
        `VC`.`Id_Capacitacion`             AS `Id_Padre`,
        `VC`.`Id_Detalle_de_Capacitacion`  AS `Id_Version_Para_Consultar`,
        
        /* Datos Informativos */
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,
        `VC`.`Nombre_Tema`                 AS `Tema`,
        `VC`.`Nombre_Instructor`           AS `Instructor`,
        
        /* Fechas (Vital para el filtro de año) */
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        
        /* Estado del Curso (Aquí saldrá 'FINALIZADO', 'CANCELADO', etc.) */
        `VC`.`Estatus_Curso`,
        `VC`.`Codigo_Estatus`,
        
        /* ¿Está eliminado lógicamente? (Para pintarlo gris en el reporte) */
        `Cap`.`Activo`                     AS `Registro_Vigente_Sistema`,
        
        /* Métricas Finales */
        `VC`.`Asistentes_Reales`           AS `Total_Asistentes`

    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* Join con el padre para saber si fue eliminado globalmente (pero igual lo mostramos) */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    WHERE 
        /* 1. FILTRO DE VERSIÓN ÚNICA:
           Solo traemos la versión que quedó como "Activa" en el detalle.
           Esto evita que salgan duplicados si el curso tuvo 5 ediciones.
           Traemos la "Foto Final". */
        `VC`.`Estatus_del_Registro` = 1

        /* 2. FILTROS DINÁMICOS */
        
        /* Filtro de Año (Si envían 0 o NULL, ignora el año) */
        AND (_Anio IS NULL OR _Anio = 0 OR YEAR(`VC`.`Fecha_Inicio`) = _Anio)
        
        /* Filtro de Gerencia (Si envían NULL o 0, trae todas) */
        AND (_Id_Gerencia IS NULL OR _Id_Gerencia <= 0 OR `Cap`.`Fk_Id_CatGeren` = _Id_Gerencia)
        
        /* Filtro de Texto (Busca en Folio, Tema o Instructor) */
        AND (_Texto_Busqueda IS NULL OR _Texto_Busqueda = '' OR (
            `VC`.`Numero_Capacitacion` LIKE CONCAT('%', _Texto_Busqueda, '%') OR
            `VC`.`Nombre_Tema` LIKE CONCAT('%', _Texto_Busqueda, '%') OR
            `VC`.`Nombre_Instructor` LIKE CONCAT('%', _Texto_Busqueda, '%')
        ))

    ORDER BY `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;