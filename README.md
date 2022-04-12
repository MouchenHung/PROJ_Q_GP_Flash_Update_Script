# PROJ_Q_GP_Flash_Update_Script
Flash fw update stress-script with mctp-pldm oem ipmi command.
while (1)
  - IMAGE1\
    do steps 
  - IMAGE2\
    do steps
  - IMAGE3\
    do steps

[steps]
- Step1. Erase flash
- Step2. Write flash
- Step3. Verify flash
### USAGE
- Command: bash update_controller.sh
- LogFile: fus_log.txt
- Input image: 
  - test_img_1: [0xFF, 0x00, 0xFF, 0x00....]
  - test_img_2: [0x00, 0x01, 0x02, 0x03....0x00, 0x01, 0x02.....]
  - test_img_3: [0xFF, 0xFE, 0xFD, 0xFC....0xFF, 0xFE, 0xFD.....]
### NOTE
- Log file would be renew while new script start, so please copy it after script end.
- Input image should only given with 4k binary file.
