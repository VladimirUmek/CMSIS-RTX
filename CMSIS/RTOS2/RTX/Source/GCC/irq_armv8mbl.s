;/*
; * Copyright (c) 2016 ARM Limited. All rights reserved.
; *
; * SPDX-License-Identifier: Apache-2.0
; *
; * Licensed under the Apache License, Version 2.0 (the License); you may
; * not use this file except in compliance with the License.
; * You may obtain a copy of the License at
; *
; * http://www.apache.org/licenses/LICENSE-2.0
; *
; * Unless required by applicable law or agreed to in writing, software
; * distributed under the License is distributed on an AS IS BASIS, WITHOUT
; * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; * See the License for the specific language governing permissions and
; * limitations under the License.
; *
; * -----------------------------------------------------------------------------
; *
; * Project:     CMSIS-RTOS RTX
; * Title:       ARMv8M Baseline Exception handlers
; *
; * -----------------------------------------------------------------------------
; */


        .file    "irq_armv8mbl.s"
        .syntax  unified

        .ifndef  __DOMAIN_NS
        .equ     __DOMAIN_NS, 0
        .endif

        .equ     I_T_RUN_OFS, 28        // osInfo.thread.run offset
        .equ     TCB_SM_OFS,  48        // TCB.stack_mem offset
        .equ     TCB_SP_OFS,  56        // TCB.SP offset
        .equ     TCB_SF_OFS,  34        // TCB.stack_frame offset
        .equ     TCB_TZM_OFS, 60        // TCB.tz_memory offset

        .section ".rodata"
        .global  os_irq_cm              // Non weak library reference
os_irq_cm:
        .byte    0


        .thumb
        .section ".text"
        .align   2


        .thumb_func
        .type    SVC_Handler, %function
        .global  SVC_Handler
        .fnstart
        .cantunwind
SVC_Handler:

        MRS      R0,PSP                 // Get PSP
        LDR      R1,[R0,#24]            // Load saved PC from stack
        SUBS     R1,R1,#2               // Point to SVC instruction
        LDRB     R1,[R1]                // Load SVC number
        CMP      R1,#0
        BNE      SVC_User               // Branch if not SVC 0

        PUSH     {R0,LR}                // Save PSP and EXC_RETURN
        LDM      R0,{R0-R3}             // Load function parameters from stack
        BLX      R7                     // Call service function
        POP      {R1,R2}                // Restore PSP and EXC_RETURN
        STR      R0,[R1]                // Store function return value
        MOV      LR,R2                  // Set EXC_RETURN

SVC_Context:
        LDR      R3,=os_Info+I_T_RUN_OFS// Load address of os_Info.run
        LDMIA    R3!,{R1,R2}            // Load os_Info.thread.run: curr & next
        CMP      R1,R2                  // Check if thread switch is required
        BEQ      SVC_Exit               // Branch when threads are the same

        CBZ      R1,SVC_ContextSwitch   // Branch if running thread is deleted

SVC_ContextSave:
        .if      __DOMAIN_NS == 1
        LDR      R0,[R1,#TCB_TZM_OFS]   // Load TrustZone memory identifier
        CBZ      R0,SVC_ContextSave1    // Branch if there is no secure context
        PUSH     {R1,R2,R3,R7}          // Save registers
        MOV      R7,LR                  // Get EXC_RETURN
        BL       TZ_StoreContext_S      // Store secure context
        MOV      LR,R7                  // Set EXC_RETURN
        POP      {R1,R2,R3,R7}          // Restore registers
        .endif

SVC_ContextSave1:
        MRS      R0,PSP                 // Get PSP
        SUBS     R0,R0,#32              // Adjust PSP
        STR      R0,[R1,#TCB_SP_OFS]    // Store SP
        STMIA    R0!,{R4-R7}            // Save R4..R7
        MOV      R4,R8
        MOV      R5,R9
        MOV      R6,R10
        MOV      R7,R11
        STMIA    R0!,{R4-R7}            // Save R8..R11

SVC_ContextSave2:
        MOV      R0,LR                  // Get EXC_RETURN
        ADDS     R1,R1,#TCB_SF_OFS      // Adjust address
        STRB     R0,[R1]                // Store stack frame information

SVC_ContextSwitch:
        SUBS     R3,R3,#8               // Adjust address
        STR      R2,[R3]                // os_Info.thread.run: curr = next

SVC_ContextRestore:
        .if      __DOMAIN_NS == 1
        LDR      R0,[R2,#TCB_TZM_OFS]   // Load TrustZone memory identifier
        CBZ      R0,SVC_ContextRestore1 // Branch if there is no secure context
        PUSH     {R2,R3}                // Save registers
        BL       TZ_LoadContext_S       // Load secure context
        POP      {R2,R3}                // Restore registers
        .endif

SVC_ContextRestore1:
        MOV      R1,R2
        ADDS     R1,R1,#TCB_SF_OFS      // Adjust address
        LDRB     R0,[R1]                // Load stack frame information
        MOVS     R1,#0xFF
        MVNS     R1,R1                  // R1=0xFFFFFF00
        ORRS     R0,R1
        MOV      LR,R0                  // Set EXC_RETURN

        .if      __DOMAIN_NS == 1
        LSLS     R0,R0,#25              // Check domain of interrupted thread
        BPL      SVC_ContextRestore2    // Branch if non-secure
        LDR      R0,[R2,#TCB_SP_OFS]    // Load SP
        MSR      PSP,R0                 // Set PSP
        BX       LR                     // Exit from handler
        .else
        LDR      R0,[R2,#TCB_SM_OFS]    // Load stack memory base
        MSR      PSPLIM,R0              // Set PSPLIM
        .endif

SVC_ContextRestore2:
        LDR      R0,[R2,#TCB_SP_OFS]    // Load SP
        ADDS     R0,R0,#16              // Adjust address
        LDMIA    R0!,{R4-R7}            // Restore R8..R11
        MOV      R8,R4
        MOV      R9,R5
        MOV      R10,R6
        MOV      R11,R7
        MSR      PSP,R0                 // Set PSP
        SUBS     R0,R0,#32              // Adjust address
        LDMIA    R0!,{R4-R7}            // Restore R4..R7

SVC_Exit:
        BX       LR                     // Exit from handler

SVC_User:
        PUSH     {R4,LR}                // Save registers
        LDR      R2,=os_UserSVC_Table   // Load address of SVC table
        LDR      R3,[R2]                // Load SVC maximum number
        CMP      R1,R3                  // Check SVC number range
        BHI      SVC_Done               // Branch if out of range

        LSLS     R1,R1,#2
        LDR      R4,[R2,R1]             // Load address of SVC function

        LDM      R0,{R0-R3}             // Load function parameters from stack
        BLX      R4                     // Call service function
        MRS      R4,PSP                 // Get PSP
        STR      R0,[R4]                // Store function return value

SVC_Done:
        POP      {R4,PC}                // Return from handler

        .fnend
        .size    SVC_Handler, .-SVC_Handler


        .thumb_func
        .type    PendSV_Handler, %function
        .global  PendSV_Handler
        .fnstart
        .cantunwind
PendSV_Handler:

        PUSH     {R0,LR}                // Save EXC_RETURN
        BL       os_PendSV_Handler      // Call os_PendSV_Handler
        POP      {R0,R1}                // Restore EXC_RETURN
        MOV      LR,R1                  // Set EXC_RETURN
        B        Sys_Context

        .fnend
        .size    PendSV_Handler, .-PendSV_Handler


        .thumb_func
        .type    SysTick_Handler, %function
        .global  SysTick_Handler
        .fnstart
        .cantunwind
SysTick_Handler:

        PUSH     {R0,LR}                // Save EXC_RETURN
        BL       os_Tick_Handler        // Call os_Tick_Handler
        POP      {R0,R1}                // Restore EXC_RETURN
        MOV      LR,R1                  // Set EXC_RETURN
        B        Sys_Context

        .fnend
        .size   SysTick_Handler, .-SysTick_Handler


        .thumb_func
        .type    Sys_Context, %function
        .global  Sys_Context
        .fnstart
        .cantunwind
Sys_Context:

        LDR      R3,=os_Info+I_T_RUN_OFS// Load address of os_Info.run
        LDM      R3!,{R1,R2}            // Load os_Info.thread.run: curr & next
        CMP      R1,R2                  // Check if thread switch is required
        BEQ      Sys_ContextExit        // Branch when threads are the same

Sys_ContextSave:
        .if      __DOMAIN_NS == 1
        LDR      R0,[R1,#TCB_TZM_OFS]   // Load TrustZone memory identifier
        CBZ      R0,Sys_ContextSave1    // Branch if there is no secure context
        PUSH     {R1,R2,R3,R7}          // Save registers
        MOV      R7,LR                  // Get EXC_RETURN
        BL       TZ_StoreContext_S      // Store secure context
        MOV      LR,R7                  // Set EXC_RETURN
        POP      {R1,R2,R3,R7}          // Restore registers
        LSLS     R7,R7,#25              // Check domain of interrupted thread
        BMI      Sys_ContextSave1       // Branch if secure
        MRS      R0,PSP                 // Get PSP
        STR      R0,[R1,#TCB_SP_OFS]    // Store SP
        B        Sys_ContextSave2
        .endif

Sys_ContextSave1:
        MRS      R0,PSP                 // Get PSP
        SUBS     R0,R0,#32              // Adjust address
        STR      R0,[R1,#TCB_SP_OFS]    // Store SP
        STMIA    R0!,{R4-R7}            // Save R4..R7
        MOV      R4,R8
        MOV      R5,R9
        MOV      R6,R10
        MOV      R7,R11
        STMIA    R0!,{R4-R7}            // Save R8..R11

Sys_ContextSave2:
        MOV      R0,LR                  // Get EXC_RETURN
        ADDS     R1,R1,#TCB_SF_OFS      // Adjust address
        STRB     R0,[R1]                // Store stack frame information

Sys_ContextSwitch:
        SUBS     R3,R3,#8               // Adjust address
        STR      R2,[R3]                // os_Info.run: curr = next

Sys_ContextRestore:
        .if      __DOMAIN_NS == 1
        LDR      R0,[R2,#TCB_TZM_OFS]   // Load TrustZone memory identifier
        CBZ      R0,Sys_ContextRestore1 // Branch if there is no secure context
        PUSH     {R2,R3}                // Save registers
        BL       TZ_LoadContext_S       // Load secure context
        POP      {R2,R3}                // Restore registers
        .endif

Sys_ContextRestore1:
        MOV      R1,R2
        ADDS     R1,R1,#TCB_SF_OFS      // Adjust offset
        LDRB     R0,[R1]                // Load stack frame information
        MOVS     R1,#0xFF
        MVNS     R1,R1                  // R1=0xFFFFFF00
        ORRS     R0,R1
        MOV      LR,R0                  // Set EXC_RETURN

        .if      __DOMAIN_NS == 1
        LSLS     R0,R0,#25              // Check domain of interrupted thread
        BPL      Sys_ContextRestore2    // Branch if non-secure
        LDR      R0,[R2,#TCB_SP_OFS]    // Load SP
        MSR      PSP,R0                 // Set PSP
        BX       LR                     // Exit from handler
        .else
        LDR      R0,[R2,#TCB_SM_OFS]    // Load stack memory base
        MSR      PSPLIM,R0              // Set PSPLIM
        .endif

Sys_ContextRestore2:
        LDR      R0,[R2,#TCB_SP_OFS]    // Load SP
        ADDS     R0,R0,#16              // Adjust address
        LDMIA    R0!,{R4-R7}            // Restore R8..R11
        MOV      R8,R4
        MOV      R9,R5
        MOV      R10,R6
        MOV      R11,R7
        MSR      PSP,R0                 // Set PSP
        SUBS     R0,R0,#32              // Adjust address
        LDMIA    R0!,{R4-R7}            // Restore R4..R7

Sys_ContextExit:
        BX       LR                     // Exit from handler

        .fnend
        .size    Sys_Context, .-Sys_Context


        .end
