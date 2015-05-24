from django.db import models

class Article(models.Model):
    sujet = models.CharField(max_length=100)
    auteur = models.CharField(max_length=42)
    message = models.TextField(null=True)
    
    def __str__(self):
        return self.sujet