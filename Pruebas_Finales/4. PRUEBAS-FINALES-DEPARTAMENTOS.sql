/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO DEPARTAMENTOS
   =================================================================================
   OBJETIVO:
   Verificar el ciclo de vida completo:
   1. Registro con "Triple Restricción".
   2. Visualización y Consultas.
   3. Edición con validación de "Integridad Geográfica".
   4. Bloqueos de Estatus (Padre Inactivo).
   5. Eliminación Física.
   ================================================================================= */

USE Picade;

/* ---------------------------------------------------------------------------------
   PRE-REQUISITOS: GENERAR DATOS GEOGRÁFICOS DE PRUEBA
   Necesitamos un entorno controlado para las pruebas.
   --------------------------------------------------------------------------------- */
-- 1. Crear Ruta Geográfica A (La "Correcta")
CALL SP_RegistrarUbicaciones('M_DEP_A', 'MUNICIPIO DEP A', 'E_DEP_A', 'ESTADO DEP A', 'P_DEP_A', 'PAIS DEP A');

-- Recuperamos IDs
SET @IdPaisA = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_DEP_A');
SET @IdEdoA  = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_DEP_A');
SET @IdMunA  = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_DEP_A');

-- 2. Crear Ruta Geográfica B (La "Otra") para pruebas de movilidad
CALL SP_RegistrarUbicaciones('M_DEP_B', 'MUNICIPIO DEP B', 'E_DEP_B', 'ESTADO DEP B', 'P_DEP_B', 'PAIS DEP B');

SET @IdPaisB = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_DEP_B');
SET @IdEdoB  = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_DEP_B');
SET @IdMunB  = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_DEP_B');

/* =================================================================================
   FASE 1: REGISTRO Y REGLAS DE UNICIDAD (LA TRIADA)
   Objetivo: Probar que la unicidad (Código + Nombre + Municipio) funcione.
   ================================================================================= */

-- 1.1. Registro Exitoso (Happy Path)
-- [ESPERADO]: Mensaje 'Departamento registrado exitosamente', Accion 'CREADA'.
CALL SP_RegistrarDepartamento('DEP-001', 'RECURSOS HUMANOS', 'EDIFICIO CENTRAL PISO 1', @IdMunA);

-- Guardamos ID para pruebas
SET @IdDep1 = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'DEP-001' AND Fk_Id_Municipio_CatDep = @IdMunA);

-- 1.2. Prueba de Idempotencia (Re-enviar lo mismo)
-- [ESPERADO]: Mensaje '...ya existe...', Accion 'REUSADA'.
CALL SP_RegistrarDepartamento('DEP-001', 'RECURSOS HUMANOS', 'OTRA DIRECCION NO IMPORTA', @IdMunA);

-- 1.3. Prueba de Flexibilidad de Nombre (Mismo Código, Mismo Lugar, Diferente Nombre) -> DEBE PASAR
-- [ESPERADO]: Accion 'CREADA' (Se permite tener DEP-001 "RH" y DEP-001 "NOMINAS" si así lo desean, aunque es raro).
CALL SP_RegistrarDepartamento('DEP-001', 'NOMINAS', 'OFICINA 2', @IdMunA);

-- 1.4. Prueba de Flexibilidad Geográfica (Mismo Código, Mismo Nombre, DIFERENTE Municipio) -> DEBE PASAR
-- [ESPERADO]: Accion 'CREADA' (Podemos tener RH en el Municipio A y RH en el Municipio B).
CALL SP_RegistrarDepartamento('DEP-001', 'RECURSOS HUMANOS', 'SUCURSAL NORTE', @IdMunB);
SET @IdDepB = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'DEP-001' AND Fk_Id_Municipio_CatDep = @IdMunB);

/* =================================================================================
   FASE 2: LECTURA Y VISTAS
   Objetivo: Verificar que los datos se recuperen correctamente.
   ================================================================================= */

-- 2.1. Listado Admin (Vista Completa)
-- [ESPERADO]: Deben salir 3 registros (2 en MunA, 1 en MunB) con sus nombres de ubicación.
CALL SP_ListarDepAdmin();

-- 2.2. Listado Activos (Para Dropdowns Globales)
-- [ESPERADO]: Solo ID, Código y Nombre.
CALL SP_ListarDepActivos();

-- 2.3. Consulta Específica (Para Edición)
-- [ESPERADO]: Debe traer los IDs de la jerarquía (Pais, Estado, Municipio) para llenar los selects.
CALL SP_ConsultarDepartamentoEspecifico(@IdDep1);

/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD GEOGRÁFICA
   Objetivo: Verificar validaciones de mudanza y duplicidad al editar.
   ================================================================================= */

-- 3.1. Prueba "Sin Cambios"
-- [ESPERADO]: Mensaje 'No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarDepartamento(@IdDep1, 'DEP-001', 'RECURSOS HUMANOS', 'EDIFICIO CENTRAL PISO 1', @IdPaisA, @IdEdoA, @IdMunA);

-- 3.2. Prueba "Ubicación Frankenstein" (Integridad Atómica)
-- Intentamos mover el departamento diciendo: País A, Estado A... pero MUNICIPIO B (que es del País B).
-- [ESPERADO]: 🔴 ERROR: "ERROR DE INTEGRIDAD: La ubicación seleccionada es inconsistente..."
CALL SP_EditarDepartamento(@IdDep1, 'DEP-001', 'RH EDITADO', 'DIR', @IdPaisA, @IdEdoA, @IdMunB);

-- 3.3. Prueba de Duplicidad en Edición
-- Intentamos cambiar el nombre de @IdDep1 para que sea igual al del paso 1.3 ('NOMINAS') en el mismo municipio.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE DUPLICIDAD: Ya existe otro Departamento..."
CALL SP_EditarDepartamento(@IdDep1, 'DEP-001', 'NOMINAS', 'DIR', @IdPaisA, @IdEdoA, @IdMunA);

-- 3.4. Edición Correcta (Mudanza Real)
-- Movemos el departamento del Municipio A al Municipio B.
-- [ESPERADO]: Accion 'ACTUALIZADA'.
CALL SP_EditarDepartamento(@IdDep1, 'DEP-001-MUDADO', 'RH MUDADO', 'NUEVA OFICINA', @IdPaisB, @IdEdoB, @IdMunB);

/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS JERÁRQUICOS
   Objetivo: Verificar que el departamento respete el estatus de su municipio.
   ================================================================================= */

-- 4.1. Desactivar Departamento (Baja Lógica)
-- [ESPERADO]: Mensaje 'Departamento Desactivado'.
CALL SP_CambiarEstatusDepartamento(@IdDep1, 0);

-- 4.2. Intentar Reactivar con Municipio Inactivo
-- Paso A: Desactivamos el Municipio B (donde vive ahora el departamento).
CALL SP_CambiarEstatusMunicipio(@IdMunB, 0);

-- Paso B: Intentamos reactivar el Departamento.
-- [ESPERADO]: 🔴 ERROR: "BLOQUEO JERÁRQUICO: No se puede ACTIVAR... porque su MUNICIPIO está INACTIVO."
CALL SP_CambiarEstatusDepartamento(@IdDep1, 1);

-- 4.3. Reactivación Correcta
-- Reactivamos Municipio -> Reactivamos Departamento.
CALL SP_CambiarEstatusMunicipio(@IdMunB, 1);
CALL SP_CambiarEstatusDepartamento(@IdDep1, 1); -- [OK]

/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS JERÁRQUICOS (CORREGIDO)
   ================================================================================= */

-- 4.1. Desactivar Departamento (Baja Lógica)
-- Desactivamos el principal que estamos probando
CALL SP_CambiarEstatusDepartamento(@IdDep1, 0);

-- [NUEVO] ¡IMPORTANTE! También debemos desactivar el otro departamento que creamos en el paso 1.4
-- Si no lo hacemos, el Municipio B no nos dejará cerrarlo.
CALL SP_CambiarEstatusDepartamento(@IdDepB, 0); 

-- 4.2. Intentar Reactivar con Municipio Inactivo
-- Paso A: Desactivamos el Municipio B. (Ahora sí dejará, porque no tiene hijos activos)
CALL SP_CambiarEstatusMunicipio(@IdMunB, 0); -- [AHORA SÍ DARÁ OK]

-- Paso B: Intentamos reactivar el Departamento @IdDep1.
-- Aquí esperamos el error porque su padre (MunB) acabamos de apagarlo.
-- [ESPERADO]: 🔴 ERROR: "BLOQUEO JERÁRQUICO: No se puede ACTIVAR... porque su MUNICIPIO está INACTIVO."
CALL SP_CambiarEstatusDepartamento(@IdDep1, 1);

-- 4.3. Corrección
-- Reactivamos Municipio -> Reactivamos Departamento.
CALL SP_CambiarEstatusMunicipio(@IdMunB, 1);
CALL SP_CambiarEstatusDepartamento(@IdDep1, 1); -- [OK]
/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA
   Objetivo: Limpieza final.
   ================================================================================= */

-- 5.1. Eliminar Departamento @IdDep1
-- [ESPERADO]: 'El Departamento ha sido eliminado permanentemente...'
CALL SP_EliminarDepartamentoFisico(@IdDep1);

-- 5.2. Limpieza de datos de prueba restantes
-- (El resto de departamentos creados y las ubicaciones)
DELETE FROM Cat_Departamentos WHERE Codigo LIKE 'DEP-001%'; 
CALL SP_EliminarMunicipio(@IdMunA);
CALL SP_EliminarMunicipio(@IdMunB);
CALL SP_EliminarEstadoFisico(@IdEdoA);
CALL SP_EliminarEstadoFisico(@IdEdoB);
CALL SP_EliminarPaisFisico(@IdPaisA);
CALL SP_EliminarPaisFisico(@IdPaisB);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO DEPARTAMENTOS
   Si pasaste los errores rojos controlados, el módulo es seguro.
   ================================================================================= */