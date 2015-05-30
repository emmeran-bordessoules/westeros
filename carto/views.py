from django.shortcuts import render
from vote.models import scoreDep

def home(request):

	sd=scoreDep.objects.all()
	return render(request,'carto/carto.html',{'sd':sd})
