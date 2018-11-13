Serial_Take     Segment
        Assume  CS:Serial_Take,DS:Nothing       ;Overhead

        ORG     100H                            ;Beginning
Start:          Jmp     Get_Busy                ;Init at end

                CR              EQU  0DH
                LF              EQU  0AH
                FF              EQU  0CH
                Port            equ  03F8H
                Pic             equ  21H
                PicDat          equ  0EFH
;--------Data area----------------------------------------
Count           DW 0090D                ;Preliminary Count
Busyflag        DB 0                    ;Reserved for the Deja-Vu flag
Skip_Char       DW 0
Print_Flag      DB 0

FileName        DB 'C:\Rdata\Report  .000',0    ;Name of file
Handle          DW 0                    ;Handle function
Num_to_write    DW 0                    ;Number of Bytes

MyStack         DB 32d dup ("Stack   ")
EndStack:

Buff_Scan       DW offset Buffer        ;For scanning
Buffer_Used     DW 0
Buffer_Pos_In   DW offset Buffer
Buffer          DB 8192d dup (0)        ;Buffer for Disk writing,Char printing
Buffer_End:
Line_Buffer     DB 200 dup (0)

Save_Stack_O    DW 0
Save_Stack_S    DW 0                    ;Stack provided for serial vector

Busy_Vector     DD ?                    ;Busy Vector
Old_Int28       DD ?                    ;DosOK Vector
Old_Tick        DD ?                    ;Timer Tick Vector (Make 08H)
Old_Int17       DD ?                    ;Old Printer vector
Diag1           DB 'Bdos Vector'
Old_Bdos        DD ?                    ;Int 21 vector

Failed1         DB CR,LF
                DB 'Error writing File',CR,LF           ;22
Failed2         DB CR,LF
                DB 'Printer will not print !!!',CR,LF   ;31

Mess1           DB 'Serial vector set',CR,LF,'$'        ;Diagnostics
Mess2           DB 'DosOk vector Set',CR,LF,'$'
Mess3           DB 'Bdos vector set',CR,LF,'$'
Mess4           DB 'Int 17 vector set',CR,LF,'$'
Mess5           DB 'Tick vector set',CR,LF,'$'
Mess6           DB 'Busy vector Gotten',CR,LF,'$'
Mess7           DB 'Got to the init portion',CR,LF,'$'

So_this_is_it   DB 'So this is it, we',39
                DB 're going to die!'  ;JUST FOR FUN
;---------------------------------------------------------------------
Serial          Proc    Far
                Assume  DS:Serial_Take,ES:Nothing
;---------------------------------------------------------------------
                push    ax
Make_Stack:     Mov     Word PTR CS:Save_Stack_S,SS    ;Save Stack segment
                Mov     Word PTR CS:Save_Stack_O,SP     ;Save Stack Offset
                Mov     SP,Offset Endstack              ;Our Stack pointer
                Mov     AX,CS                           ;At current
                Mov     SS,AX                           ;Segment

                push    ds
                push    bx
                push    cx
                push    dx
                push    es
                push    si              ;Save ax,bx,cx,dx,ds,es,si
                Push    di
                Push    CS
                Pop     DS
;-------All saved ---------------------------------------------------
                mov     dx,Port+2       ;Check if Char received
                in      al,dx                   ;Read IIR
                cmp     al,4            ;Char received ?
                jne     Skip_Serial     ;No char, go away
;-------------------------------------------------------------
Buffer_It:      Or      Busyflag,01        ;Set RxData
                mov     dx,Port                 ;Get port address
                in      al,dx                   ;Get a char
                Cmp     al,26d                  ;End of Report ?
                Je      End_Report              ;Yes, flag it

                mov     cx,[Buffer_used]          ;Character Counter
                mov     si,[Buffer_Pos_In]        ;Buffer Offset
                mov     [si],al                 ;Place in buffer
                inc     si                      ;Step buffer position
                inc     cx                      ;Step Counter
                mov     [Buffer_used],cx          ;Save Counter
                mov     [Buffer_Pos_In],si        ;Save Input Position
                jmp     Skip_Serial             ;No , Skip on
End_Report:     Mov     al,0Ch                  ;Port status byte
                Mov     DX,Port+4               ;At status port
                Out     DX,al                   ;Handshake off
                Mov     al,FF                   ;Get a form feed
                Mov     si,[Buffer_Pos_In]         ;Forgot this one
                Mov     [si],al                 ;Place form feed
                Mov     si,offset Buffer        ;Reset input position
                Mov     [Buffer_Pos_In],si      ;Save it
                Mov     CX,[Buffer_Used]        ;Get Last position
                Mov     [Num_to_write],cx       ;Set Write length
                Or      Busyflag,0Eh       ;Set RTP and RPW
Skip_Serial:    Pop     di
                pop     si
                pop     es
                pop     dx
                pop     cx
                pop     bx
                pop     DS
                Mov     SS,Word PTR CS:Save_Stack_S ;Restore segment
                Mov     SP,Word PTR CS:Save_Stack_O ;And pointer

                mov     al,PIC-1
                out     PIC-1,al                ;End of Interrupt command
                pop     ax                      ;Pop last few goodies
                iret                            ;And go home
Serial          Endp
;---------------------------------------------------------------------------
New_Bdos        Proc    Far
                Assume  DS:Nothing,ES:Nothing
                Pushf                           ;Save the flags
                Test    CS:Busyflag,2           ;Anything in buffer ?
                Jnz     File_Function           ;Try it
                Jmp     No_Can_Do               ;Or pass thru
File_Function:  Push    DS                      ;Check Dos Busy
                Push    BX
                LDS     BX,CS:Busy_Vector       ;Get location of DosBusy
                Cmp     Byte PTR [BX],0         ;Compare to 0
                Pop     BX
                Pop     DS
                Jne     No_Can_Do               ;Dos unavailable
                Call    Do_File                  ;Or do Dos functions
No_Can_Do:      Or      AH,AH                   ;Function 0?
                Jne     Check_Change            ;No,Check if changing vector
                Mov     AX,4C00H                ;Make it Function 4C
                Jp      Not_Needed
;3/24/92
Check_Change:   Cmp     AH,25H                  ;Is someone changing a vector
                Jne     Not_Needed              ;
                Cmp     AL,28H                  ;Is it INT28H
                Jne     Not_Needed              ;No, skip outta town
                Mov     Word PTR [Old_Int28],BX ;Else make my exit point to it
                Mov     Word PTR [Old_Int28+2],ES
                Popf
                Xor     AL,AL
                Iret
Not_Needed:     Popf                            ;Restore flags
                CLI
                Jmp     CS:Old_Bdos             ;Do original Dos Function

New_Bdos        Endp
;---------------------------------------------------------------------------
Do_File          Proc    Near
                Assume  DS:Nothing,ES:Nothing
                Push    AX
                Push    BX
                Push    CX
                Push    DX
                Push    DS
                Push    ES
                Push    CS
                Pop     DS                      ;Set up addressing
        Assume  DS:Serial_Take                  ;Tell the assembler
                And     Busyflag,0F4h           ;Set file written
                Mov     AX,3524H                ;Get critical error Vector
                Call    Bdos
                Push    BX
                Push    ES                      ;Save it on stack
                Mov     DX,Offset New_Int24
                Mov     AX,2524H                ;Dos set vector
                Call    Bdos
;Severe error vector replaced
                Cmp     Num_to_write,0          ;Something to write ?
                Je      Restore_n_go            ;No, go away
                Mov     DX,Offset FileName      ;Point to filename
                Mov     AX,3D02h                ;Open it
                Call    Bdos
                Jc      Open_Failed             ;Can't open it
                Mov     BX,AX                   ;Handle in BX also
                Xor     CX,CX                   ;Pointer offset
                Xor     DX,DX                   ;zero past end
                Mov     AX,4202H                ;Append to file
                Call    Bdos
                Jc      Close_it                ;Jump if failed
                Jmp     Short Write_Data        ;OK, write it
Open_Failed:    Cmp     AX,2
                Jne     Restore_n_go            ;Not a file not found, quit
                Mov     CX,0020H                ;New file attribute
                Mov     AH,3CH                  ;Create file
                Call    Bdos
                Jc      Close_it                ;Error jump
                Mov     BX,AX                   ;Save handle
Write_Data:     Mov     DX,offset Buffer        ;Point to Buffer
                Mov     CX,Num_to_write         ;Number of characters
                Mov     AH,40H                  ;Write to file
                Call    Bdos                    ;Do it
                Jc      Close_it                ;Error jump
                Cmp     CX,AX                   ;All written ?
                Jne     Close_it                ;if not, Error
                Jmp     Close_File
Close_it:       Mov     DX,offset Failed1       ;Generic error message
                Mov     CX,22d
                Mov     AH,40H
                Call    Bdos
Close_File:     Mov     AH,3EH                  ;Close file
                Call    Bdos
Restore_n_go:   Mov     Num_to_write,0          ;Clear file buffer length

Print_it:       Test    Busyflag,32             ;Printer Ownership
                Jz      Not_Print               ;Don't own it
                And     Busyflag,88H
                Or      Busyflag,64             ;Claim the printer
                Mov     BX,4                    ;Handle for printer
                Mov     AH,40h                  ;Write function
                Mov     CX,Buffer_Used          ;Number characters
                Mov     DX,offset Buffer        ;Starting at
                Int     21h
                Mov     Buffer_Used,0
                Mov     Buffer_Pos_In,Offset Buffer
                And     Busyflag,098H           ;Done with printer
Not_Print:
                Pop     DS
                Pop     DX
                Mov     AX,2524H                ;Restore Critical error
                Call    Bdos
        Assume  DS:Nothing
                Pop     ES
                Pop     DS
                Pop     DX
                Pop     CX
                Pop     BX
                Pop     AX
                Ret
Do_File          Endp
;---------------------------------------------------------------------------
Bdos            Proc    Near
        Assume  DS:Nothing,ES:Nothing
                Pushf
                CLI
                Call    CS:Old_Bdos
                STI
                RET
Bdos            Endp
;---------------------------------------------------------------------------
New_Int24       Proc    Far
        Assume  DS:Nothing,ES:nothing
                STI                             ;Turn interrupts on
                Xor     AL,AL                   ;Ignore the error
                Mov     CS:Busyflag,0           ;Clear flags
                Iret                            ;And go back
New_Int24       Endp
;---------------------------------------------------------------------------
New_Int17       Proc    Far
                Assume  DS:Nothing,ES:Nothing
                Cmp     DX,0
                Je      My_Printer
Bypass:         Jmp     CS:Old_Int17            ;Not my printer
My_Printer:     Test    CS:Busyflag,64          ;Us printing ?
                Jnz     Bypass                  ;Yes, Go thru
                Test    CS:Busyflag,32          ;Not called but ours ?
                Jnz     B_Ret                   ;It's busy !
                Mov     CS:Count,90             ;Timeout function reset
Test_file:      Test    CS:Busyflag,2           ;File data ready ?
                Jnz     Write_needed            ;Yes
                Jmp     Short Bypass
Write_Needed:
                Push    BX
                LDS     BX,CS:Busy_vector       ;Get a busy message
                Cmp     Byte Ptr [BX],0         ;Is Dos BUSY ?
                Pop     BX
                Pop     DS
                Jne     Bypass                  ;It is, get off here
                Call    Do_File                  ;Write the data
                Jmp     Short Bypass

B_ret:          Mov     AH,00010000B            ;Printer Busy
                Stc                             ;Set Carry
                Iret
New_Int17       Endp
;---------------------------------------------------------------------------
New_Tick        Proc    Far
                Assume  DS:Nothing,ES:Nothing
                Pushf                           ;Simulate interrupt
                Call    CS:Old_Tick             ;Call original timer
                Test    CS:Busyflag,64          ;Are we printing ?
                Jnz     Not_Ready               ;Yes, Git
                Cmp     CS:Count,0              ;Count = 0 ?
                Jz      Done_Count              ;Yes, Count no further
                Dec     CS:Count                ;Count down
Done_Count:     Test    CS:Busyflag,4           ;File to print ?
                Jz      Check_File              ;Else check the write
                Or      CS:Busyflag,34          ;Set a need to print
Check_File:     Test    CS:Busyflag,2           ;Flag set ?
                Jnz     Not_Ready               ;No need to set it then
                Test    CS:Busyflag,8           ;File to write ?
                Jz      No_Need                 ;No, all done
                Or      CS:Busyflag,2           ;Needed

Not_Ready:      Iret                            ;And return

No_Need:        Mov     CS:Count,90
                Mov     CS:Busyflag,0           ;Reset flags
                Push    AX
                Push    DX
                Mov     DX,Port+4               ;Control port
                Mov     AL,0DH                  ;Get the DTR line on
                Out     DX,AL
                Pop     DX
                Pop     AX
                Iret                            ;'n go home
New_Tick        Endp
;---------------------------------------------------------------------------
New_Int28       Proc    Far
                Assume  DS:Nothing,ES:Nothing

                STI
                Test    CS:Busyflag,2           ;Anything Goin ?
                Jz      Gone                    ;No, scram
                Call    Do_File                 ;Or Do it
Gone:           Jmp     CS:Old_Int28

New_Int28       Endp
End_Res:
;---------------------------------------------------------------------

        Assume  CS:Serial_Take,DS:Serial_Take,ES:Nothing

Get_Busy:
;--------------------------------------------------------------------------
                Push    CS
                Pop     DS
                Mov     AH,09H
                Mov     DX,offset Mess7
                Int     21H
;--------------------------------------------------------------------------
                Mov     AH,34H                  ;Find busy flag address
                Int     21H                     ;Call DOS
                Push    CS                      ;Current Segment (CS)
                Pop     DS                      ;Data Segment (DS)
                Mov     Word PTR [Busy_Vector]  ,BX      ;Save low vector
                Mov     Word PTR [Busy_Vector+2],ES      ;Save high vector
;--------------------------------------------------------------------------
                Mov     AH,09H
                Mov     DX,offset Mess6
                Int     21H
;---------------------------------------------------------------------------
Get_Tick:       Mov     AX,3508H                ;Get Vector 08 function *****
                Int     21H                     ;Get Tick vector
                Mov     Word PTR [Old_Tick]  ,BX ;Offset of vector
                Mov     Word PTR [Old_Tick+2],ES ;Segment of vector
Set_Tick:       Mov     DX,Offset New_Tick      ;Point to program (DS:DX)
                Mov     AX,2508H                ;DOS set Tick vector
                Int     21H                     ;Call DOS
;---------------------------------------------------------------------------
Get_Int17:      Mov     AX,3517H                ;Get Vector 17 function *
                Int     21H                     ;Get Print vector
                Mov     Word PTR [Old_Int17]    ,BX     ;Save Offset
                Mov     Word PTR [Old_Int17 +2] ,ES     ;Save Segment
Set_Int17:      Mov     DX,Offset New_int17     ;Point to program (DS:DX)
                Mov     AX,2517H                ;DOS set Print vector
                Int     21H                     ;Call DOS
;---------------------------------------------------------------------------
Get_Bdos:       Mov     AX,3521H                ;Set Int 21H
                Int     21H
                Mov     Word PTR [Old_Bdos]     ,BX
                Mov     Word PTR [Old_Bdos+2]   ,ES     ;Save Old_Bdos vector
Set_Bdos:       Mov     DX,Offset New_Bdos              ;Point to here
                Mov     AX,2521H
                Int     21H
;--------------------------------------------------------------------------
                Mov     AH,09H
                Mov     DX,offset Mess3
                Int     21H
;---------------------------------------------------------------------------
Init_Ser:       mov     ah,0            ;Set Serial
                mov     al,83H          ;1200,8,n,1
                mov     dx,0            ;Port 0
                int     14H             ;Call Bios
;--------------------------------------------------------------------------
                mov     dx,Port+1
                mov     al,01           ;Interrupt Enable Register
                out     dx,al           ;Data Recieved interrupt
                in      al,PIC
                and     al,PicDat       ;Enable IRQ4
                out     PIC,al          ;At Interrupt Controller
                mov     dx,Port+4
                mov     al,0DH          ;IRQ 4
                out     dx,al           ;Turn Hardware out and Handshake on
;--------------------------------------------------------------------------
Set_Ser_Vect:   Mov     DX,Offset Serial        ;DS:DX is vector
                Mov     AX,250CH                ;DOS set Com1 vector
                Int     21H                     ;Call DOS
;--------------------------------------------------------------------------
                Mov     AH,09H
                Mov     DX,offset Mess1
                Int     21H
;---------------------------------------------------------------------------
Get_DosOK:      Mov     AX,3528H                ;Get Vector 28H function
                Int     21H                     ;Get Kbd vector
                Mov     Word PTR [Old_Int28]  ,BX    ;Offset of vector
                Mov     Word PTR [Old_INT28+2],ES    ;Segment of vector
Set_DosOK:      Mov     DX,Offset New_Int28     ;DS:DX is vector
                Mov     AX,2528H                ;DOS set DosOK vector
                Int     21H                     ;Call DOS
;--------------------------------------------------------------------------
                Mov     AH,09H
                Mov     DX,offset Mess2
                Int     21H

;---------------------------------------------------------------------------
                Mov     DX,(Offset End_Res-Serial_Take+100H)/16  ;Set part that stays
                Mov     AX,3100H           ;DOS advanced function KEEP
                Int     21H                     ;Terminate and eat memory
Init            ENDP        ;End of procedure (Assy overhead)
Serial_Take     ENDS        ;End of segment (see above)
                END     Start         ;B'duh,b'duh,b'duh that's all folks


