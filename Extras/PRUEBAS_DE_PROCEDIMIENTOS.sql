SELECT * FROM picade.vista_direcciones limit 3000;

Call SP_BuscadorGlobalUbicaciones ('');

Call SP_BuscadorGlobalUbicaciones ('P');

-- SHOW PROCEDURE STATUS

CALL SP_RegistrarUbicacionCompleta(
    'MIA', 'MIAMI',          -- 1. Municipio
    'FL',  'FLORIDA',        -- 2. Estado
    'USA', 'ESTADOS UNIDOS'  -- 3. País
);

CALL SP_RegistrarUbicacionCompleta(
    'LAX', 'LOS ANGELES',          -- 1. Municipio
    'CL',  'CALIFORNIA',        -- 2. Estado
    'USA', 'ESTADOS UNIDOS'  -- 3. País
);

SELECT * FROM Vista_Direcciones WHERE Codigo_Estado or Nombre_Estado = 'Florida';
CALL SP_BuscadorGlobalUbicaciones('FL');

SELECT * FROM picade.vista_direcciones limit 3000;

SELECT * FROM `PICADE`.`Pais` limit 3000;

SHOW TABLE STATUS LIKE 'Cat_Estatus_Participante';
SHOW TABLE STATUS LIKE 'Municipio';
SHOW TABLE STATUS LIKE 'Estado';
SHOW TABLE STATUS LIKE 'Pais';
SHOW TABLE STATUS LIKE 'Info_Personal';
SHOW TABLE STATUS LIKE 'Cat_Roles';


