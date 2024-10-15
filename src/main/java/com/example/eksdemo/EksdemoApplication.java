package com.example.eksdemo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class EksdemoApplication {

	@GetMapping("/")
	public String getEks(){
		return "EKS Demo";
	}



	public static void main(String[] args) {
		SpringApplication.run(EksdemoApplication.class, args);
	}

}
