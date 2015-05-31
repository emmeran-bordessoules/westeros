from django.db import models

class Comment(models.Model):
	auteur = models.CharField(max_length=200)
	texte = models.TextField()
			
	def __str__(self):
		return self.texte
		
class compteur(models.Model):
	compteur=models.IntegerField(default=8)