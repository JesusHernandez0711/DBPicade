USE `Picade`;

/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO REGÍMENES
   =================================================================================
   OBJETIVO:
   Simular el ciclo de vida completo de un Régimen de Contratación:
   1. Registro (Happy Path, Idempotencia, Reactivación).
   2. Validaciones de Duplicidad (Identidad Dual).
   3. Consultas y Vistas (Admin vs Operativo).
   4. Edición (Idempotencia, Cambio de Identidad, Concurrencia simulada).
   5. Candados de Estatus (Dependencia de Empleados).
   6. Eliminación Física (Dependencia de Empleados).
   ================================================================================= */

/* ---------------------------------------------------------------------------------
   FASE 0: LIMPIEZA PREVIA (Opcional, para reiniciar pruebas)
   --------------------------------------------------------------------------------- */
-- DELETE FROM Cat_Regimenes_Trabajo WHERE Codigo LIKE 'REG-QA%';

/* =================================================================================
   FASE 1: REGISTRO Y REGLAS DE UNICIDAD
   Objetivo: Verificar creación, sanitización y manejo de duplicados.
   ================================================================================= */
/* =================================================================================
   FASE 1: REGISTRO Y REGLAS DE UNICIDAD (LÓGICA ESTRICTA: TODO OBLIGATORIO)
   Objetivo: Verificar creación, validación de obligatoriedad y manejo de duplicados.
   ================================================================================= */

-- 1.1. Registro Exitoso (Happy Path)
-- [ESPERADO]: Mensaje 'Régimen registrado exitosamente', Accion 'CREADA'.
CALL SP_RegistrarRegimen('REG-QA-01', 'REGIMEN DE PRUEBA ALPHA', 'DESCRIPCION INICIAL');

-- Guardamos ID para pruebas posteriores
SET @IdReg1 = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'REG-QA-01');


-- 1.2. PRUEBA DE BLINDAJE (Intentar registrar NULL) - ¡NUEVO!
-- Intentamos violar la regla de "Todo es obligatorio".
-- [ESPERADO]: 🔴 ERROR 1644: "ERROR DE VALIDACIÓN: El CÓDIGO del Régimen es obligatorio."
-- (Si sale este error, el sistema es SEGURO).
CALL SP_RegistrarRegimen(NULL, 'REGIMEN SIN CODIGO', 'SIN DESC');


-- 1.3. Registro del Segundo Dato (Ahora sí, con datos correctos)
-- Como el paso anterior falló (correctamente), ahora lo insertamos bien para poder usarlo en las siguientes pruebas.
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarRegimen('REG-QA-02', 'REGIMEN BETA', 'DESCRIPCION BETA');

-- Guardamos el ID del segundo registro
SET @IdReg2 = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'REG-QA-02');


-- 1.4. Prueba de Idempotencia por CÓDIGO (Re-enviar lo mismo del 1.1)
-- [ESPERADO]: Mensaje '...ya se encuentra registrado...', Accion 'REUSADA'.
CALL SP_RegistrarRegimen('REG-QA-01', 'REGIMEN DE PRUEBA ALPHA', 'OTRA DESC');


-- 1.5. Conflicto de Identidad Cruzada (Mismo Código, diferente Nombre)
-- Intentamos usar el código 'REG-QA-01' con otro nombre.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE CONFLICTO: El CÓDIGO ingresado ya existe..."
CALL SP_RegistrarRegimen('REG-QA-01', 'NOMBRE IMPOSTOR', 'DESC');


-- 1.6. Conflicto de Identidad Cruzada (Mismo Nombre, diferente Código)
-- Intentamos usar el nombre 'REGIMEN DE PRUEBA ALPHA' con otro código.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE CONFLICTO: El NOMBRE ingresado ya existe..."
CALL SP_RegistrarRegimen('REG-QA-99', 'REGIMEN DE PRUEBA ALPHA', 'DESC');


/* =================================================================================
   FASE 2: LECTURA Y VISTAS
   Objetivo: Verificar que la UI reciba los datos correctos.
   ================================================================================= */

-- 2.1. Listado Admin (Vista Completa)
-- [ESPERADO]: Deben salir los 2 registros creados. Verificar columnas Estatus_Regimen.
CALL SP_ListarRegimenesAdmin();

-- 2.2. Listado Activos (Dropdown Operativo)
-- [ESPERADO]: Solo ID, Código y Nombre. Deben salir ambos (porque nacen activos).
CALL SP_ListarRegimenesActivos();

-- 2.3. Consulta Específica (Para Edición)
-- [ESPERADO]: Datos crudos. Verificar que @IdReg2 tenga Código en NULL.
CALL SP_ConsultarRegimenEspecifico(@IdReg1);
CALL SP_ConsultarRegimenEspecifico(@IdReg2);


/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD
   Objetivo: Verificar validaciones al modificar datos.
   ================================================================================= */

-- 3.1. Prueba "Sin Cambios"
-- [ESPERADO]: Mensaje 'No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarRegimen(@IdReg1, 'REG-QA-01', 'REGIMEN DE PRUEBA ALPHA', 'DESCRIPCION INICIAL');

-- 3.2. Prueba de Duplicidad Global (Robar código de otro)
-- Intentamos ponerle al Reg2 el código del Reg1.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE DUPLICIDAD: El CÓDIGO ya pertenece a otro Régimen."
CALL SP_EditarRegimen(@IdReg2, 'REG-QA-01', 'REGIMEN SIN CODIGO BETA', 'DESC');

-- 3.3. Prueba de Duplicidad Global (Robar nombre de otro)
-- Intentamos ponerle al Reg2 el nombre del Reg1.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE DUPLICIDAD: El NOMBRE ya pertenece a otro Régimen."
CALL SP_EditarRegimen(@IdReg2, 'COD-X', 'REGIMEN DE PRUEBA ALPHA', 'DESC');

-- 3.4. Edición Correcta (Enriquecimiento)
-- Le asignamos un código al Regimen 2 que no tenía.
-- [ESPERADO]: Mensaje 'Régimen actualizado correctamente', Accion 'ACTUALIZADA'.
CALL SP_EditarRegimen(@IdReg2, 'REG-QA-02', 'REGIMEN BETA EVOLUCIONADO', 'AHORA TIENE CODIGO');


/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS DE INTEGRIDAD (SIMULACIÓN DE EMPLEADOS)
   Objetivo: Verificar que no se pueda desactivar si hay uso.
   ================================================================================= */

-- 4.1. Desactivar Régimen 1 (Baja Lógica - Sin empleados aún)
-- [ESPERADO]: Mensaje 'Régimen Desactivado'.
CALL SP_CambiarEstatusRegimen(@IdReg1, 0);

-- 4.2. Verificar Listado Operativo
-- [ESPERADO]: El REG-QA-01 NO debe aparecer en el dropdown.
CALL SP_ListarRegimenesActivos();

-- 4.3. Reactivar Régimen 1
-- [ESPERADO]: Mensaje 'Régimen Reactivado'.
CALL SP_CambiarEstatusRegimen(@IdReg1, 1);

-- 4.4. SIMULACIÓN DE CANDADO (Inyectamos un empleado dummy)
-- Nota: Esto requiere que tengas un catalogo de Puestos/CT activos o usar IDs dummy si no validas FKs estrictas en Info_Personal aun.
-- INSERT INTO `Info_Personal` (Nombre, Apellido_Paterno, Apellido_Materno, Fk_Id_CatRegimen, Activo) 
-- VALUES ('EMPLEADO', 'TEST', 'QA', @IdReg1, 1);
-- SET @IdEmpleadoDummy = LAST_INSERT_ID();

-- 4.5. Intentar Desactivar con Empleado Activo
-- [ESPERADO]: 🔴 ERROR: "BLOQUEO DE INTEGRIDAD: No se puede desactivar... existen EMPLEADOS ACTIVOS..."
-- CALL SP_CambiarEstatusRegimen(@IdReg1, 0);

-- 4.6. Liberar Candado (Desactivar o borrar empleado)
-- UPDATE `Info_Personal` SET Activo = 0 WHERE Id_InfoPersonal = @IdEmpleadoDummy;
-- O DELETE FROM `Info_Personal` WHERE Id_InfoPersonal = @IdEmpleadoDummy;

-- 4.7. Intentar Desactivar de nuevo
-- [ESPERADO]: Ahora sí debe dejar.
CALL SP_CambiarEstatusRegimen(@IdReg1, 0);


/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA
   Objetivo: Limpieza final y prueba de Hard Delete.
   ================================================================================= */

-- 5.1. Eliminar Régimen 2
-- [ESPERADO]: 'Registro eliminado permanentemente...'
CALL SP_EliminarRegimenFisico(@IdReg2);

-- 5.2. Eliminar Régimen 1
CALL SP_EliminarRegimenFisico(@IdReg1);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO REGÍMENES
   ================================================================================= */