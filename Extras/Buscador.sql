/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */
/* PROCEDIMIENTO DE ALMACENADO PARA BUSCAR UBICACIONES/DIRECCIONES (VERSIÓN PAGINADA)                     */
/* ====================================================================================== */
/* 1. BUSCADOR GLOBAL (V2: PAGINACIÓN + CONTROL DE CARGA)                                 */
/* ====================================================================================== */
/* ======================================================================================
   PROCEDIMIENTO: SP_BuscadorUbicacionesV2
   ======================================================================================
   OBJETIVO
   --------
   Buscar coincidencias parciales en Municipio / Estado / País, con:
   - paginación (LIMIT + OFFSET)
   - control de carga (límite máximo)
   - opción de incluir inactivos (para pantallas admin)

   PARÁMETROS
   ----------
   _textoBusqueda:
     - NULL / ''  => devuelve listado inicial (ej: "primera página")
     - con valor  => busca con LIKE en 6 campos (Código/Nombre de los 3 niveles)

   _soloActivos:
     - 1 => solo Municipios activos (Estatus=1)
     - 0 => incluye activos e inactivos (admin)

   _Limit:
     - cantidad de filas a devolver (por defecto 50)
     - se limita a un máximo para evitar abusos (ej. 500)

   _Offset:
     - desde qué fila empezar (paginación)

   NOTA DE PERFORMANCE
   -------------------
   - LIKE '%texto%' no usa índices (en general). Por eso es CRÍTICO limitar resultados.
====================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS SP_BuscadorUbicacionesV2$$
CREATE PROCEDURE SP_BuscadorUbicacionesV2(
    IN _textoBusqueda VARCHAR(150),
    IN _soloActivos TINYINT,     /* 1=solo activos, 0=incluir inactivos */
    IN _Limit INT,               /* tamaño de página */
    IN _Offset INT               /* salto de página */
)
BEGIN
    /* ------------------------------------------------------------
       NORMALIZACIÓN DE PARAMETROS
    ------------------------------------------------------------ */
    SET _textoBusqueda = NULLIF(TRIM(_textoBusqueda), '');
    SET _soloActivos   = IFNULL(_soloActivos, 1);

    /* Límite por defecto y "candado" para evitar consultas enormes */
    SET _Limit  = IFNULL(_Limit, 50);
    SET _Offset = IFNULL(_Offset, 0);

    /* Ajustes defensivos */
    IF _Limit < 1 THEN SET _Limit = 50; END IF;
    IF _Limit > 500 THEN SET _Limit = 500; END IF;
    IF _Offset < 0 THEN SET _Offset = 0; END IF;

    /* ------------------------------------------------------------
       CASO 1: SIN TEXTO => LISTADO INICIAL
    ------------------------------------------------------------ */
    IF _textoBusqueda IS NULL THEN

        SELECT *
        FROM `Picade`.`Vista_Direcciones`
        WHERE (_soloActivos = 0 OR Estatus = 1)
        ORDER BY Nombre_Pais, Nombre_Estado, Nombre_Municipio
        LIMIT _Offset, _Limit;

    ELSE

        /* ------------------------------------------------------------
           CASO 2: CON TEXTO => BUSQUEDA PARCIAL EN 6 CAMPOS
        ------------------------------------------------------------ */
        SELECT *
        FROM `Picade`.`Vista_Direcciones`
        WHERE (_soloActivos = 0 OR Estatus = 1)
          AND (
              Codigo_Municipio LIKE CONCAT('%', _textoBusqueda, '%') OR
              Nombre_Municipio LIKE CONCAT('%', _textoBusqueda, '%') OR
              Codigo_Estado    LIKE CONCAT('%', _textoBusqueda, '%') OR
              Nombre_Estado    LIKE CONCAT('%', _textoBusqueda, '%') OR
              Codigo_Pais      LIKE CONCAT('%', _textoBusqueda, '%') OR
              Nombre_Pais      LIKE CONCAT('%', _textoBusqueda, '%')
          )
        ORDER BY Nombre_Pais, Nombre_Estado, Nombre_Municipio
        LIMIT _Offset, _Limit;

    END IF;
END$$

DELIMITER ;

