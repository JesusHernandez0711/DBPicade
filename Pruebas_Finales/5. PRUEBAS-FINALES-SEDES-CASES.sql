USE `Picade`;

/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO SEDES (CASES)
   =================================================================================
   OBJETIVO:
   Simular el ciclo de vida completo de una Sede:
   1. Registro (con y sin inventario).
   2. Validación de Duplicidad (Identidad).
   3. Integridad Geográfica (Sedes huérfanas).
   4. Edición y Mudanza.
   5. Candados de Estatus (Dependencia del Municipio).
   6. Eliminación Física.
   ================================================================================= */

/* ---------------------------------------------------------------------------------
   FASE 0: PREPARACIÓN DEL ENTORNO (DATOS SEMILLA)
   Necesitamos Ubicaciones válidas para probar la integridad referencial.
   --------------------------------------------------------------------------------- */

-- 1. Ruta A (Para pruebas estándar)
CALL SP_RegistrarUbicaciones('M_CASES_A', 'MUNICIPIO CASES A', 'E_CASES_A', 'ESTADO CASES A', 'P_CASES_A', 'PAIS CASES A');
SET @IdPaisA = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_CASES_A');
SET @IdEdoA  = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_CASES_A');
SET @IdMunA  = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_CASES_A');

-- 2. Ruta B (Para pruebas de mudanza y bloqueo jerárquico)
CALL SP_RegistrarUbicaciones('M_CASES_B', 'MUNICIPIO CASES B', 'E_CASES_B', 'ESTADO CASES B', 'P_CASES_B', 'PAIS CASES B');
SET @IdPaisB = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_CASES_B');
SET @IdEdoB  = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_CASES_B');
SET @IdMunB  = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_CASES_B');


/* =================================================================================
   FASE 1: REGISTRO, SANITIZACIÓN Y NORMALIZACIÓN
   Objetivo: Verificar que se guarde la data y que los NULLs se conviertan a 0.
   ================================================================================= */

-- 1.1. Registro Completo (Sede con infraestructura definida)
-- [ESPERADO]: Mensaje 'Sede registrada exitosamente', Accion 'CREADA'.
CALL SP_RegistrarSede(
    'CASES-001',            -- Código
    'CENTRO DE ADIESTRAMIENTO ALPHA',  -- Nombre
    'AVENIDA SIEMPRE VIVA 123', -- Dirección
    @IdMunA,                -- Municipio
    100, -- Capacidad Total
    5,   -- Aulas
    2,   -- Salas
    1,   -- Alberca
    1,   -- Campos
    0,   -- Muelle
    20   -- Botes
);

-- Guardamos ID para pruebas
SET @IdSede1 = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'CASES-001');

-- 1.2. Registro con NULLs (Prueba de Sanitización)
-- Enviamos NULL en infraestructura para probar que el SP guarda ceros (0) y no rompe la BD.
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarSede(
    'CASES-002', 
    'OFICINA ENLACE BETA (SIN INFRA)', 
    NULL,      -- Sin dirección
    @IdMunA, 
    NULL, NULL, NULL, NULL, NULL, NULL, NULL -- Todo NULL
);

SET @IdSede2 = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'CASES-002');

-- 1.3. Prueba de Idempotencia (Re-enviar lo mismo)
-- Intentamos registrar la Sede 1 otra vez con los mismos datos.
-- [ESPERADO]: Mensaje '...ya existe...', Accion 'REUSADA'.
CALL SP_RegistrarSede('CASES-001', 'CENTRO DE ADIESTRAMIENTO ALPHA', 'OTRA DIR', @IdMunA, 100,5,2,1,1,0,20);


/* =================================================================================
   FASE 2: VALIDACIONES DE INTEGRIDAD Y DUPLICIDAD
   Objetivo: Intentar romper las reglas de negocio.
   ================================================================================= */

-- 2.1. Conflicto de Identidad por CÓDIGO
-- Intentamos registrar otro nombre con el código de la Sede 1.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE CONFLICTO: El CÓDIGO ingresado ya existe..."
CALL SP_RegistrarSede('CASES-001', 'NOMBRE IMPOSTOR', 'DIR', @IdMunA, 0,0,0,0,0,0,0);

-- 2.2. Conflicto de Identidad por NOMBRE
-- Intentamos registrar otro código con el nombre de la Sede 1.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE CONFLICTO: El NOMBRE ingresado ya existe..."
CALL SP_RegistrarSede('CASES-999', 'CENTRO DE ADIESTRAMIENTO ALPHA', 'DIR', @IdMunA, 0,0,0,0,0,0,0);

-- 2.3. Integridad del Padre (Municipio Inexistente)
-- [ESPERADO]: 🔴 ERROR: "ERROR DE INTEGRIDAD: El Municipio seleccionado no existe..."
CALL SP_RegistrarSede('CASES-ERR', 'SEDE ERROR', 'DIR', 99999, 0,0,0,0,0,0,0);


/* =================================================================================
   FASE 3: LECTURA Y VISTAS
   Objetivo: Verificar que la UI reciba los datos jerárquicos e inventario.
   ================================================================================= */

-- 3.1. Listado Admin (Vista Completa)
-- [ESPERADO]: Deben salir 2 registros. Verificar columna 'Nombre_Municipio'.
CALL SP_ListarSedesAdmin();

-- 3.2. Listado Activos (Dropdown)
-- [ESPERADO]: Solo ID, Código y Nombre.
CALL SP_ListarSedesActivas();

-- 3.3. Consulta Específica (Para Edición)
-- [ESPERADO]: Debe traer los IDs de País y Estado (reconstrucción jerárquica) y el inventario detallado.
-- Verifica que la Sede 2 traiga '0' en Aulas y no 'NULL'.
CALL SP_ConsultarSedeEspecifica(@IdSede1);
CALL SP_ConsultarSedeEspecifica(@IdSede2);


/* =================================================================================
   FASE 4: EDICIÓN E INTEGRIDAD GEOGRÁFICA
   Objetivo: Verificar validaciones de mudanza y actualización de inventario.
   ================================================================================= */

-- 4.1. Prueba "Sin Cambios"
-- [ESPERADO]: Mensaje 'No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
-- (Nota: Debes pasar los mismos valores de inventario que tenía).
CALL SP_EditarSede(@IdSede1, 'CASES-001', 'CENTRO DE ADIESTRAMIENTO ALPHA', 'AVENIDA SIEMPRE VIVA 123', @IdPaisA, @IdEdoA, @IdMunA, 100, 5, 2, 1, 1, 0, 20);

-- 4.2. Prueba "Ubicación Frankenstein" (Integridad Atómica)
-- Intentamos mover la sede diciendo: País A, Estado A... pero MUNICIPIO B (que es del País B).
-- [ESPERADO]: 🔴 ERROR: "ERROR DE INTEGRIDAD: La ubicación seleccionada es incoherente..."
CALL SP_EditarSede(@IdSede1, 'CASES-001', 'CENTRO ALPHA', 'DIR', @IdPaisA, @IdEdoA, @IdMunB, 100, 5, 2, 1, 1, 0, 20);

-- 4.3. Edición Correcta (Mudanza y Actualización de Inventario)
-- Movemos la Sede 1 al Municipio B y le "construimos" 10 Aulas más (Total 15).
-- [ESPERADO]: Accion 'ACTUALIZADA'.
CALL SP_EditarSede(@IdSede1, 'CASES-001', 'CENTRO MUDADO A BETA', 'NUEVA DIRECCION', @IdPaisB, @IdEdoB, @IdMunB, 200, 15, 2, 1, 1, 0, 20);


/* =================================================================================
   FASE 5: ESTATUS Y CANDADOS JERÁRQUICOS
   Objetivo: Verificar que la Sede respete el estatus de su Municipio.
   ================================================================================= */

-- 5.1. Desactivar Sede (Baja Lógica)
-- [ESPERADO]: Mensaje 'Sede Desactivada'.
CALL SP_CambiarEstatusSede(@IdSede1, 0);

-- 5.2. Verificar Listado Operativo
-- [ESPERADO]: La Sede 1 NO debe aparecer en el dropdown de activos.
CALL SP_ListarSedesActivas();

-- 5.3. Intentar Reactivar con Municipio Inactivo
-- Paso A: Desactivamos el Municipio B (donde ahora vive la Sede 1).
CALL SP_CambiarEstatusMunicipio(@IdMunB, 0);

-- Paso B: Intentamos reactivar la Sede.
-- [ESPERADO]: 🔴 ERROR: "BLOQUEO JERÁRQUICO: No se puede ACTIVAR... porque su MUNICIPIO está INACTIVO."
CALL SP_CambiarEstatusSede(@IdSede1, 1);

-- 5.4. Reactivación Correcta
-- Reactivamos Municipio -> Reactivamos Sede.
CALL SP_CambiarEstatusMunicipio(@IdMunB, 1);
CALL SP_CambiarEstatusSede(@IdSede1, 1); -- [OK]


/* =================================================================================
   FASE 6: ELIMINACIÓN FÍSICA
   Objetivo: Limpieza y prueba de Hard Delete.
   ================================================================================= */

-- 6.1. Eliminar Sede 2
-- [ESPERADO]: 'La Sede ha sido eliminada permanentemente...'
CALL SP_EliminarSedeFisica(@IdSede2);

-- 6.2. Limpieza General
CALL SP_EliminarSedeFisica(@IdSede1);
CALL SP_EliminarMunicipio(@IdMunA);
CALL SP_EliminarMunicipio(@IdMunB);
CALL SP_EliminarEstadoFisico(@IdEdoA);
CALL SP_EliminarEstadoFisico(@IdEdoB);
CALL SP_EliminarPaisFisico(@IdPaisA);
CALL SP_EliminarPaisFisico(@IdPaisB);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO SEDES
   Si pasaste los errores rojos controlados, el módulo es seguro y robusto.
   ================================================================================= */