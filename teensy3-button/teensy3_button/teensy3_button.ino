void setup() {
  pinMode(0, INPUT);
}

void loop() {
  if (digitalRead(0)) {
    Keyboard.print('p');
    delay(3000);
  }

  delay(10);
}
