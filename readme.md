DE10_Lite QC workflow

## All programming can also be done manually using the Quartus Programmer, but I will provide instructions assuming the use of the Powershell script

---

1. Run program_many.bat, this will initialize the powershell script (ignoring the warning about it being unsigned), this avoids needing to explicitly use PowerShell.
2. Press OK once the first DE10 is connected to begin. 

![](images\firstdialogue.png)

3. select Yes to start the flashing process.

![](images\seconddialogue.png)

4. A new dialog will pop up once programing is complete. If the programming has failed, retry it at least once, as JTAG errors are common. if it repeatedly fails, the device is likely damaged. 

![](images\thirddialogue.png)

5. Ensure that the leds are all fully functional. This can be done by pressing KEY0, the button closest to the VGA port. If the device is functional, set it aside in a "working devices" section. If it is not working, set it aside in a "damaged devices" section. 

6. If you have another DE10-Lite to process, select Ok. If done, press Cancel. Continue from step 2. 

![](images\fourthdialogue.png)

