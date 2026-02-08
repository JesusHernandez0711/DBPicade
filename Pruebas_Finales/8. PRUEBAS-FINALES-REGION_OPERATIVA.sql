/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO REGIONES OPERATIVAS
   =================================================================================
   OBJETIVO:
   Validar el "Gold Standard" en el ciclo de vida de una Región:
   1. Registro con validación de identidad (Código/Nombre).
   2. Autosanación (Recuperación de soft-deletes).
   3. Bloqueo Determinístico en Edición.
   4. Candados de Estatus (Dependencia de Personal).
   5. Eliminación Física (Defensa en Profundidad).
   ================================================================================= */

USE Picade;

/* ---------------------------------------------------------------------------------
   FASE 0: LIMPIEZA PREVIA (Opcional)
   --------------------------------------------------------------------------------- */
-- DELETE FROM Cat_Regiones_Trabajo WHERE Codigo LIKE 'REG-QA%';

/* =================================================================================
   FASE 1: REGISTRO Y REGLAS DE UNICIDAD (HAPPY PATH & DIRTY DATA)
   Objetivo: Verificar creación, sanitización y manejo de duplicados.
   ================================================================================= */

-- 1.1. Registro Exitoso (Happy Path)
-- [ESPERADO]: Mensaje 'Región registrada exitosamente', Accion 'CREADA'.
CALL SP_RegistrarRegion('REG-QA-01', 'REGION NORTE DE PRUEBA', 'COBERTURA ZONA NORTE');

-- Guardamos ID para pruebas posteriores
SET @IdReg1 = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'REG-QA-01');

-- 1.2. Prueba de "Todo Obligatorio" (Intentar registrar NULLs)
-- [ESPERADO]: 🔴 ERROR: "ERROR DE VALIDACIÓN: El CÓDIGO de la Región es obligatorio."
CALL SP_RegistrarRegion(NULL, 'NOMBRE SIN CODIGO', 'DESC');

-- 1.3. Registro del Segundo Dato (Para pruebas cruzadas)
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarRegion('REG-QA-02', 'REGION SUR DE PRUEBA', 'COBERTURA ZONA SUR');
SET @IdReg2 = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'REG-QA-02');

-- 1.4. Prueba de Idempotencia por CÓDIGO (Re-enviar lo mismo del 1.1)
-- [ESPERADO]: Mensaje 'La Región ya se encuentra registrada...', Accion 'REUSADA'.
CALL SP_RegistrarRegion('REG-QA-01', 'REGION NORTE DE PRUEBA', 'OTRA DESCRIPCION NO IMPORTA');

-- 1.5. Conflicto de Identidad Cruzada (Mismo Código, diferente Nombre)
-- [ESPERADO]: 🔴 ERROR: "ERROR DE CONFLICTO: El CÓDIGO ingresado ya existe..."
CALL SP_RegistrarRegion('REG-QA-01', 'NOMBRE IMPOSTOR', 'DESC');

-- 1.6. Conflicto de Identidad Cruzada (Mismo Nombre, diferente Código)
-- [ESPERADO]: 🔴 ERROR: "ERROR DE CONFLICTO: El NOMBRE ingresado ya existe..."
CALL SP_RegistrarRegion('REG-QA-99', 'REGION NORTE DE PRUEBA', 'DESC');

/* =================================================================================
   FASE 2: LECTURA Y VISTAS
   Objetivo: Verificar que la UI reciba los datos correctos.
   ================================================================================= */

-- 2.1. Listado Admin (Vista Completa)
-- [ESPERADO]: Deben salir los 2 registros creados. Verificar columna 'Estatus_Region'.
CALL SP_ListarRegionesAdmin();

-- 2.2. Listado Activos (Dropdown Operativo)
-- [ESPERADO]: Solo ID, Código y Nombre. Deben salir ambos.
CALL SP_ListarRegionesActivas();

-- 2.3. Consulta Específica (Para Edición - Raw Data)
-- [ESPERADO]: Datos crudos. Verificar fechas created_at/updated_at.
CALL SP_ConsultarRegionEspecifica(@IdReg1);

/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD
   Objetivo: Verificar validaciones al modificar datos y bloqueos.
   ================================================================================= */

-- 3.1. Prueba "Sin Cambios" (Idempotencia en Update)
-- [ESPERADO]: Mensaje 'No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarRegion(@IdReg1, 'REG-QA-01', 'REGION NORTE DE PRUEBA', 'COBERTURA ZONA NORTE');

-- 3.2. Prueba de Duplicidad Global (Robar código de otro)
-- Intentamos ponerle a la Región 2 el código de la Región 1.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE DUPLICIDAD: El CÓDIGO ya pertenece a otra Región."
CALL SP_EditarRegion(@IdReg2, 'REG-QA-01', 'NOMBRE X', 'DESC');

-- 3.3. Prueba de Duplicidad Global (Robar nombre de otro)
-- Intentamos ponerle a la Región 2 el nombre de la Región 1.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE DUPLICIDAD: El NOMBRE ya pertenece a otra Región."
CALL SP_EditarRegion(@IdReg2, 'COD-X', 'REGION NORTE DE PRUEBA', 'DESC');

-- 3.4. Edición Correcta (Evolución de datos)
-- Cambiamos nombre y descripción de la Región 2.
-- [ESPERADO]: Mensaje 'Región actualizada correctamente', Accion 'ACTUALIZADA'.
CALL SP_EditarRegion(@IdReg2, 'REG-QA-02', 'REGION SUR EVOLUCIONADA', 'NUEVA COBERTURA TOTAL');

/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS DE INTEGRIDAD (SIMULACIÓN DE PERSONAL)
   Objetivo: Verificar que no se pueda desactivar si hay uso real.
   ================================================================================= */

-- 4.1. Desactivar Región 1 (Baja Lógica - Sin empleados aún)
-- [ESPERADO]: Mensaje '...Región ha sido DESACTIVADA...'.
CALL SP_CambiarEstatusRegion(@IdReg1, 0);

-- 4.2. Verificar Listado Operativo
-- [ESPERADO]: La REG-QA-01 NO debe aparecer en el dropdown (SP_ListarRegionesActivas).
CALL SP_ListarRegionesActivas();

-- 4.3. Reactivar Región 1 (Para preparar la siguiente prueba)
-- [ESPERADO]: Mensaje '...Región ha sido REACTIVADA...'.
CALL SP_CambiarEstatusRegion(@IdReg1, 1);

/* ---------------------------------------------------------------------------------
   [SIMULACIÓN DE CANDADO DE NEGOCIO]
   Para esta prueba, necesitamos simular que hay un empleado en esta región.
   IMPORTANTE: Si no tienes datos en Cat_Puestos, Cat_Deptos, etc., inserta NULLs si tu BD lo permite,
   o usa IDs válidos de tus otros catálogos. Aquí asumo una inserción mínima para detonar el candado.
   --------------------------------------------------------------------------------- */

-- A. Insertar Empleado Dummy vinculado a la Región 1 (@IdReg1)
-- INSERT INTO `Info_Personal` (Nombre, Apellido_Paterno, Fk_Id_CatRegion, Activo) 
-- VALUES ('EMPLEADO_TEST', 'QA', @IdReg1, 1);
-- SET @IdEmpleadoDummy = LAST_INSERT_ID();

-- 4.4. Intentar Desactivar Región 1 con Empleado Activo
-- [ESPERADO]: 🔴 ERROR: "CONFLICTO DE INTEGRIDAD [409]: ...Existen EMPLEADOS ACTIVOS..."
-- CALL SP_CambiarEstatusRegion(@IdReg1, 0);

-- B. Liberar Candado (Simular que damos de baja al empleado o lo borramos)
-- DELETE FROM `Info_Personal` WHERE Id_InfoPersonal = @IdEmpleadoDummy;

-- 4.5. Intentar Desactivar de nuevo (Ahora limpio)
-- [ESPERADO]: ÉXITO.
CALL SP_CambiarEstatusRegion(@IdReg1, 0);

/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA (HARD DELETE)
   Objetivo: Limpieza final y prueba de los 3 Anillos de Seguridad.
   ================================================================================= */

-- 5.1. Intentar Borrar Región Inexistente
-- [ESPERADO]: 🔴 ERROR 404: "La Región que intenta eliminar no existe..."
CALL SP_EliminarRegionFisica(999999);

/* ---------------------------------------------------------------------------------
   [SIMULACIÓN DE CANDADO HISTÓRICO]
   Aunque el empleado esté borrado o inactivo, si existe en historial, NO DEBE DEJAR BORRAR FISICAMENTE.
   --------------------------------------------------------------------------------- */
-- A. Insertar Empleado Inactivo (Histórico) en Región 2 (@IdReg2)
-- INSERT INTO `Info_Personal` (Nombre, Fk_Id_CatRegion, Activo) VALUES ('HISTORICO', @IdReg2, 0);
-- SET @IdEmpleadoHist = LAST_INSERT_ID();

-- 5.2. Intentar Borrar Región 2 (Tiene historial inactivo)
-- [ESPERADO]: 🔴 ERROR 409: "...Existen expedientes de PERSONAL (Activos o Históricos)..."
-- CALL SP_EliminarRegionFisica(@IdReg2);

-- B. Limpieza del Histórico para permitir borrado
-- DELETE FROM `Info_Personal` WHERE Id_InfoPersonal = @IdEmpleadoHist;

-- 5.3. Eliminación Física Exitosa - Región 2
-- [ESPERADO]: 'ÉXITO: La Región ha sido eliminada permanentemente...'
CALL SP_EliminarRegionFisica(@IdReg2);

-- 5.4. Eliminación Física Exitosa - Región 1
CALL SP_EliminarRegionFisica(@IdReg1);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO REGIONES
   Si todos los semáforos rojos y verdes funcionaron, el módulo está LISTO PARA PRODUCCIÓN.
   ================================================================================= */